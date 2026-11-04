%% ==================== final14.m ====================
% Non-learning predictor baseline (recency + frequency), 5 trials.
%
% 리뷰어 지적: "APJ 의 이득이 단순한 채널 반복 통계(최근 채널 / 최빈 채널)로
% 설명되지 않는가?" -> TimeSlotP 로 확인. 논문에는 Overall 문단에 한 줄로만 보고.
%
% 재머 (B_J = 2):
%   1) Target 이 직전 슬롯에 사용한 채널
%   2) 최근 HISTORY_WINDOW 슬롯 동안 최빈 채널 (1 과 같으면 2순위)
% 정찰 구간: 관측만. 공격 구간: 위 규칙으로 재밍.
% 같은 seed(100~104), 같은 정찰/공격 길이, 같은 재밍 예산 (final11/12 과 동일).
%
% 저장: final14_results.mat

clc; clear; clear variables; clear DebugHelper; close all;

numTrials      = 5;
baseSeed       = 100;
trialSeeds     = baseSeed + (0:numTrials-1);
HISTORY_WINDOW = 50;
TOPK_JAM       = 2;

env;
totalSlots        = numTimeSlots;
reconDurationUsed = reconnaissanceDuration;

fprintf("\n============================================================\n");
fprintf(" Non-learning predictor (recency + frequency) baseline\n");
fprintf("============================================================\n");
fprintf(" Trials       : %d\n", numTrials);
fprintf(" Total slots  : %d\n", totalSlots);
fprintf(" Recon        : %d\n", reconDurationUsed);
fprintf(" History win  : %d\n", HISTORY_WINDOW);
fprintf(" B_J          : %d\n", TOPK_JAM);
fprintf("============================================================\n");

hitRateResults = nan(1, numTrials);
successResults = nan(1, numTrials);
sinrResults    = nan(1, numTrials);
hitSeries      = nan(numTrials, totalSlots);
ackSeries      = nan(numTrials, totalSlots);

for trial = 1:numTrials
    seed = trialSeeds(trial);
    fprintf("\n[Predictor] Trial %d / %d (Seed=%d)\n", trial, numTrials, seed);
    [hitRateResults(trial), successResults(trial), sinrResults(trial), ...
        hitSeries(trial,:), ackSeries(trial,:)] = ...
        runPredictor(seed, totalSlots, TOPK_JAM, HISTORY_WINDOW);
end

meanHit  = mean(hitRateResults, 'omitnan');  stdHit  = std(hitRateResults, 0, 'omitnan');
meanSuc  = mean(successResults, 'omitnan');  stdSuc  = std(successResults, 0, 'omitnan');
meanSinr = mean(sinrResults, 'omitnan');     stdSinr = std(sinrResults, 0, 'omitnan');
ciHit  = compute95CI(hitRateResults);
ciSuc  = compute95CI(successResults);
ciSinr = compute95CI(sinrResults);

fprintf("\n============================================================\n");
fprintf(" Predictor (recency+frequency, W=%d) — Final Results\n", HISTORY_WINDOW);
fprintf("============================================================\n");
fprintf(" per-trial JHR : %s\n", mat2str(hitRateResults, 4));
fprintf(" JHR  %.2f%% ± %.2f (95%% CI ± %.2f)\n", meanHit, stdHit, ciHit);
fprintf(" ACK  %.2f%% ± %.2f (95%% CI ± %.2f)\n", meanSuc, stdSuc, ciSuc);
fprintf(" SINR %.3f dB ± %.3f (95%% CI ± %.3f)\n", meanSinr, stdSinr, ciSinr);
fprintf("============================================================\n");

save('final14_results.mat', 'numTrials', 'trialSeeds', 'HISTORY_WINDOW', 'TOPK_JAM', ...
    'totalSlots', 'reconDurationUsed', ...
    'hitRateResults', 'successResults', 'sinrResults', 'hitSeries', 'ackSeries', ...
    'meanHit', 'stdHit', 'meanSuc', 'stdSuc', 'meanSinr', 'stdSinr', ...
    'ciHit', 'ciSuc', 'ciSinr');
fprintf("Saved: final14_results.mat\n");


%% ================================================================
%  Local Functions
% ================================================================

function [hitRate, successRate, sinrDb, hitVector, ackVector] = ...
    runPredictor(seed, totalSlots, topKJam, historyWindow)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    apj = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);
    registerJammer(UTs, apj, targetUTId, false);

    timeSlotP = TimeSlotP(reconnaissanceDuration, topKJam, historyWindow);
    timeSlotP.EnableJamming = true;
    timeSlotP.Verbose = false;

    pLog = struct('slot', {}, 'observedChannel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

    for slotIndex = 1:numTimeSlots
        [timeSlotP, pLog] = timeSlotP.run(slotIndex, UTs, SatelliteNode, apj, ...
            ServiceChannels, ControlChannels, targetBeamIndex, pLog);
    end

    verifyObservation(UTs, totalSlots, "Predictor");

    hitVector = extractHitVectorGeneric(pLog, totalSlots, 'jammingChannels', 'observedChannel');
    [successRate, sinrDb, ackVector] = computeAttackUTMetrics(totalSlots);
    hitRate = mean(hitVector, 'omitnan') * 100;

    fprintf("  [Predictor]  JHR=%.2f%% | ACK=%.2f%% | SINR=%.3f dB\n", hitRate, successRate, sinrDb);
end


function registerJammer(UTs, jammer, targetUTId, selfObserve)
    for utIndex = 1:numel(UTs)
        UTs(utIndex).ObservationManager.Jammer = jammer;
    end
    if selfObserve
        jammer.ObservationManager.Jammer   = jammer;
        jammer.ObservationManager.TargetUT = UTs(targetUTId);
    end
    assert(~isempty(UTs(targetUTId).ObservationManager.Jammer), ...
        "final14:JammerNotRegistered — Target UT에 재머 미등록");
end


function verifyObservation(UTs, totalSlots, label)
    numObs = arrayfun(@(u) u.ObservationManager.NumObservations, UTs);
    if any(numObs < totalSlots)
        warning("final14:ObservationMissing", ...
            "[%s] 일부 UT의 관측 횟수가 슬롯 수보다 적습니다 (min=%d, expected>=%d).", ...
            label, min(numObs), totalSlots);
    end
end


function hitVector = extractHitVectorGeneric(logStruct, totalSlots, jammedField, targetField)
    hitVector = nan(1, totalSlots);
    if isempty(logStruct), return; end
    for idx = 1:numel(logStruct)
        slot = logStruct(idx).slot;
        if slot < 1 || slot > totalSlots, continue; end
        if ~logStruct(idx).isAttackPhase, continue; end
        jc = logStruct(idx).(jammedField);
        if isempty(jc), continue; end
        targetChannel = logStruct(idx).(targetField);
        hitVector(slot) = double(any(targetChannel == jc));
    end
end


function [successRate, sinrDb, ackVector] = computeAttackUTMetrics(totalSlots)
    evalUTData = DebugHelper.TargetUTStorage('get', []);
    successRate = NaN; sinrDb = NaN; ackVector = nan(1, totalSlots);
    if isempty(evalUTData) || isempty(evalUTData.slots), return; end
    attackIdx = logical(evalUTData.isAttackPhase);
    if any(attackIdx)
        successRate = mean(evalUTData.isACK(attackIdx)) * 100;
        sinrDb = mean(evalUTData.SINR_dB(attackIdx), 'omitnan');
    end
    for i = 1:numel(evalUTData.slots)
        if ~evalUTData.isAttackPhase(i), continue; end
        slot = evalUTData.slots(i);
        if slot < 1 || slot > totalSlots, continue; end
        ackVector(slot) = double(evalUTData.isACK(i));
    end
end


function ci = compute95CI(x)
    x = x(~isnan(x)); n = numel(x);
    if n <= 1, ci = NaN; return; end
    ci = tcrit975(n - 1) * std(x, 0) / sqrt(n);
end


function t = tcrit975(df)
    table = [12.706 4.303 3.182 2.776 2.571 2.447 2.365 2.306 2.262 2.228 ...
             2.201 2.179 2.160 2.145 2.131 2.120 2.110 2.101 2.093 2.086 ...
             2.080 2.074 2.069 2.064 2.060 2.056 2.052 2.048 2.045 2.042];
    if df < 1, t = NaN; elseif df <= numel(table), t = table(df); else, t = 1.96; end
end


function resetDebugStorage()
    DebugHelper.TargetUTStorage('reset', []);
end


function [ServiceChannels, ControlChannels] = buildChannels()
    env;
    ServiceChannels = Channel.empty(0, numChannels);
    ControlChannels = Channel.empty(0, numChannels);
    for channelIndex = 1:numChannels
        centerFreq_Hz = serviceBandStart_Hz + (channelIndex - 0.5) * channelSpacing_Hz;
        s = centerFreq_Hz - channelBandwidth_Hz / 2;
        e = centerFreq_Hz + channelBandwidth_Hz / 2;
        ServiceChannels(channelIndex) = Channel(channelIndex, ChannelType.Service, s, e);
        ControlChannels(channelIndex) = Channel(channelIndex, ChannelType.Control, 1, 2);
    end
end


function [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork()
    env;
    SatelliteNode = Satellite(9999, [0 0 satelliteAltitude], numBeams);
    Beams = BeamFactory.createBeams(numBeams, maxBeamFootprintDiameter, beamRadius, beamSpacing, ...
        beamMaxGain_dBi, beam3dBWidth_deg, beamEIRPDensity_dBW_per_MHz, channelBandwidth_Hz);
    for beamIndex = 1:numBeams
        SatelliteNode.addBeam(Beams(beamIndex));
    end
    UTs = UTFactory.createUTs(Beams, numUTs);
    targetBeamIndex = find([Beams.AssociatedUTId] == targetUTId, 1);
    if isempty(targetBeamIndex)
        error("final14:TargetBeamNotFound", "targetUTId 에 연결된 Beam을 찾을 수 없습니다.");
    end
end