%% ==================== final3.m ====================
% Attack Method Comparison — Data Generation
%
% RQ1:
%   Under the SAME attack start time and SAME attack budget,
%   which jamming method is most effective?
%
% Current implemented methods:
%   1) Random
%   2) Sweep
%   3) Comb (Fixed-Channel)
%   4) APJ (Shadow DQN)
%
%   + No-Attack baseline (재밍 없이 Target UT 성능만 측정,
%     ACK Success Rate 비교 기준선으로 사용)
%
% 이 스크립트는 시뮬레이션 실행 + raw 데이터 저장만 담당한다.
% 그래프는 final3_plot.m에서 저장된 .mat을 로드해서 그린다.
% (재실행 없이 그래프 스타일만 계속 수정 가능하게 하기 위함)

clc;
clear;
clear variables;
clear DebugHelper;
close all;

%% ================================================================
%  Configuration
% ================================================================

techniqueNames = [
    "Random"
    "Sweep"
    "Comb"
    "APJ (Shadow DQN)"
];

numTechniques = numel(techniqueNames);

% Final paper: >=5 recommended / Debug: 1~3
numTrials = 5;

baseSeed = 100;
trialSeeds = baseSeed + (0:numTrials-1);

% Moving-average window
movingWindow = 100;

% Comb 고정 채널 (mainC.m과 동일)
combFixedChannels = [3 5];


%% ================================================================
%  Load environment once to obtain numTimeSlots / Recon duration
% ================================================================

env;

totalSlots = numTimeSlots;
reconDurationUsed = reconnaissanceDuration;

fprintf("\n============================================================\n");
fprintf(" Attack Method Comparison\n");
fprintf("============================================================\n");
fprintf(" Number of trials      : %d\n", numTrials);
fprintf(" Total slots           : %d\n", totalSlots);
fprintf(" Reconnaissance        : %d\n", reconDurationUsed);
fprintf(" Attack starts at      : %d\n", reconDurationUsed + 1);
fprintf(" Moving window         : %d slots\n", movingWindow);
fprintf(" Comb fixed channels   : %s\n", mat2str(combFixedChannels));
fprintf("============================================================\n");


%% ================================================================
%  Result Storage
% ================================================================

hitRateResults = nan(numTechniques, numTrials);
successResults = nan(numTechniques, numTrials);
sinrResults    = nan(numTechniques, numTrials);

hitSeries = nan(numTechniques, numTrials, totalSlots);
ackSeries = nan(numTechniques, numTrials, totalSlots);

% No-Attack baseline (ACK Success Rate만 의미 있음, JHR/SINR 개념 없음)
baselineAckResults = nan(1, numTrials);
baselineAckSeries  = nan(numTrials, totalSlots);


%% ================================================================
%  No-Attack Baseline
% ================================================================

fprintf("\n");
fprintf("============================================================\n");
fprintf(" NO-ATTACK BASELINE\n");
fprintf("============================================================\n");

for trial = 1:numTrials

    seed = trialSeeds(trial);

    [baselineAckResults(trial), baselineAckSeries(trial, :)] = ...
        runNoAttack(seed, totalSlots);

end

baselineMeanACK = mean(baselineAckResults, 'omitnan');
baselineStdACK  = std(baselineAckResults, 0, 'omitnan');
baselineCiACK   = compute95CI(baselineAckResults);

fprintf("\n------------------------------------------------------------\n");
fprintf(" No-Attack ACK Success Rate = %.2f%% ± %.2f%% (95%% CI ± %.2f), n=%d\n", ...
    baselineMeanACK, baselineStdACK, baselineCiACK, numTrials);
fprintf("------------------------------------------------------------\n");


%% ================================================================
%  Main Experiment
% ================================================================

for trial = 1:numTrials

    seed = trialSeeds(trial);

    fprintf("\n");
    fprintf("############################################################\n");
    fprintf(" Trial %d / %d (Seed=%d)\n", trial, numTrials, seed);
    fprintf("############################################################\n");


    %% ------------------------------------------------------------
    %  1. Random
    % ------------------------------------------------------------

    [ ...
        hitRateResults(1,trial), ...
        successResults(1,trial), ...
        sinrResults(1,trial), ...
        hitSeries(1,trial,:), ...
        ackSeries(1,trial,:) ...
    ] = runRandom(seed, totalSlots);


    %% ------------------------------------------------------------
    %  2. Sweep
    % ------------------------------------------------------------

    [ ...
        hitRateResults(2,trial), ...
        successResults(2,trial), ...
        sinrResults(2,trial), ...
        hitSeries(2,trial,:), ...
        ackSeries(2,trial,:) ...
    ] = runSweep(seed, totalSlots);


    %% ------------------------------------------------------------
    %  3. Comb
    % ------------------------------------------------------------

    [ ...
        hitRateResults(3,trial), ...
        successResults(3,trial), ...
        sinrResults(3,trial), ...
        hitSeries(3,trial,:), ...
        ackSeries(3,trial,:) ...
    ] = runComb(seed, totalSlots, combFixedChannels);


    %% ------------------------------------------------------------
    %  4. APJ Shadow DQN
    % ------------------------------------------------------------

    [ ...
        hitRateResults(4,trial), ...
        successResults(4,trial), ...
        sinrResults(4,trial), ...
        hitSeries(4,trial,:), ...
        ackSeries(4,trial,:) ...
    ] = runShadowDQN(seed, totalSlots);

end


%% ================================================================
%  Aggregate Statistics
% ================================================================

meanHit = mean(hitRateResults, 2, 'omitnan');
stdHit  = std(hitRateResults, 0, 2, 'omitnan');

meanSuc = mean(successResults, 2, 'omitnan');
stdSuc  = std(successResults, 0, 2, 'omitnan');

meanSinr = mean(sinrResults, 2, 'omitnan');
stdSinr  = std(sinrResults, 0, 2, 'omitnan');

ciHit = compute95CI(hitRateResults);
ciSuc = compute95CI(successResults);
ciSinr = compute95CI(sinrResults);


%% ================================================================
%  Print Final Results
% ================================================================

fprintf("\n");
fprintf("============================================================\n");
fprintf(" Attack Method Comparison — Final Results\n");
fprintf("============================================================\n");

fprintf("%-18s : ACK %.2f%% ± %.2f (95%% CI ± %.2f)\n", ...
    "No-Attack", baselineMeanACK, baselineStdACK, baselineCiACK);

for i = 1:numTechniques

    fprintf( ...
        "%-18s : JHR %.2f%% ± %.2f | ACK %.2f%% ± %.2f | SINR %.3f dB ± %.3f\n", ...
        techniqueNames(i), ...
        meanHit(i), stdHit(i), ...
        meanSuc(i), stdSuc(i), ...
        meanSinr(i), stdSinr(i));

    fprintf( ...
        "%-18s   JHR 95%% CI ± %.2f | ACK 95%% CI ± %.2f\n", ...
        "", ciHit(i), ciSuc(i));

end

fprintf("============================================================\n");


%% ================================================================
%  Convert Slot-Level Binary Results → Moving Average
%  (그래프용으로 미리 계산해서 같이 저장 — plot 스크립트에서 재계산 불필요)
% ================================================================

slots = 1:totalSlots;

hitMoving = nan(size(hitSeries));
ackMoving = nan(size(ackSeries));


for techniqueIndex = 1:numTechniques

    for trial = 1:numTrials

        h = squeeze(hitSeries(techniqueIndex, trial, :))';
        a = squeeze(ackSeries(techniqueIndex, trial, :))';

        validHit = ~isnan(h);
        validACK = ~isnan(a);

        if any(validHit)

            firstHit = find(validHit, 1, 'first');
            lastHit  = find(validHit, 1, 'last');

            temp = movmean( ...
                h(firstHit:lastHit), ...
                movingWindow, ...
                'omitnan');

            hitMoving( ...
                techniqueIndex, ...
                trial, ...
                firstHit:lastHit) = temp;
        end


        if any(validACK)

            firstACK = find(validACK, 1, 'first');
            lastACK  = find(validACK, 1, 'last');

            temp = movmean( ...
                a(firstACK:lastACK), ...
                movingWindow, ...
                'omitnan');

            ackMoving( ...
                techniqueIndex, ...
                trial, ...
                firstACK:lastACK) = temp;
        end

    end
end


hitMoving = hitMoving * 100;
ackMoving = ackMoving * 100;

meanHitTime = squeeze(mean(hitMoving, 2, 'omitnan'));
meanACKTime = squeeze(mean(ackMoving, 2, 'omitnan'));

ciHitTime = computeTimeSeries95CI(hitMoving);
ciACKTime = computeTimeSeries95CI(ackMoving);


%% ================================================================
%  No-Attack Baseline Moving Average (그래프용)
% ================================================================

baselineAckMoving = nan(numTrials, totalSlots);

for trial = 1:numTrials

    a = baselineAckSeries(trial, :);
    validACK = ~isnan(a);

    if any(validACK)
        firstACK = find(validACK, 1, 'first');
        lastACK  = find(validACK, 1, 'last');

        temp = movmean(a(firstACK:lastACK), movingWindow, 'omitnan');
        baselineAckMoving(trial, firstACK:lastACK) = temp;
    end
end

baselineAckMoving = baselineAckMoving * 100;

meanBaselineACKTime = mean(baselineAckMoving, 1, 'omitnan');
ciBaselineACKTime   = computeTimeSeries95CI( ...
    reshape(baselineAckMoving, 1, numTrials, totalSlots));
ciBaselineACKTime   = squeeze(ciBaselineACKTime);


%% ================================================================
%  SAVE ALL RESULTS (재실행 없이 그래프만 다시 그릴 수 있도록)
% ================================================================

save('final3_results.mat', ...
    'techniqueNames', 'numTechniques', 'numTrials', 'movingWindow', ...
    'totalSlots', 'reconDurationUsed', 'combFixedChannels', 'slots', ...
    'hitRateResults', 'successResults', 'sinrResults', ...
    'hitSeries', 'ackSeries', ...
    'hitMoving', 'ackMoving', ...
    'meanHit', 'stdHit', 'meanSuc', 'stdSuc', 'meanSinr', 'stdSinr', ...
    'ciHit', 'ciSuc', 'ciSinr', ...
    'meanHitTime', 'meanACKTime', 'ciHitTime', 'ciACKTime', ...
    'baselineAckResults', 'baselineMeanACK', 'baselineStdACK', 'baselineCiACK', ...
    'baselineAckSeries', 'baselineAckMoving', ...
    'meanBaselineACKTime', 'ciBaselineACKTime', ...
    '-v7.3');

fprintf("\n");
fprintf("Numerical results saved:\n");
fprintf("  final3_results.mat\n");
fprintf("그래프는 final3_plot.m을 실행해서 그리세요 (재시뮬레이션 불필요).\n");


%% ================================================================
%  Local Functions
% ================================================================


function [ackRate, ackVector] = runNoAttack(seed, totalSlots)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);

    timeSlotDE = TimeSlotDE(2, reconnaissanceDuration);
    timeSlotDE.EnableJamming = false;   % 재밍만 끄고 evaluation phase / prediction은 그대로

    divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
        'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
        'observedChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'isAttackPhase', {}, 'jammingChannels', {});
    channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

    for slotIndex = 1:numTimeSlots
        [divergenceLog, channelLog] = timeSlotDE.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);
    end

    [~, ~, ackVector] = computeAttackUTMetrics(totalSlots);

    evalUTData = DebugHelper.TargetUTStorage('get', []);
    ackRate = NaN;
    if ~isempty(evalUTData) && ~isempty(evalUTData.slots)
        attackIdx = logical(evalUTData.isAttackPhase);
        if any(attackIdx)
            ackRate = mean(evalUTData.isACK(attackIdx)) * 100;
        end
    end

    fprintf("  [No-Attack] ACK=%.2f%%\n", ackRate);
end


function [hitRate, successRate, sinrDb, hitVector, ackVector] = ...
    runRandom(seed, totalSlots)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    apj = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);

    topKJam = 2;
    timeSlotR = TimeSlotR(topKJam);

    rLog = struct('slot', {}, 'observedChannel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

    for slotIndex = 1:numTimeSlots
        rLog = timeSlotR.run(slotIndex, UTs, SatelliteNode, apj, ServiceChannels, ControlChannels, targetBeamIndex, rLog);
    end

    hitVector = extractHitVector(rLog, totalSlots);
    [successRate, sinrDb, ackVector] = computeAttackUTMetrics(totalSlots);
    hitRate = mean(hitVector, 'omitnan') * 100;

    fprintf("  [Random]  JHR=%.2f%% | ACK=%.2f%% | SINR=%.3f dB\n", hitRate, successRate, sinrDb);
end



function [hitRate, successRate, sinrDb, hitVector, ackVector] = ...
    runSweep(seed, totalSlots)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    apj = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);

    dwellSlots = 1;
    timeSlotS = TimeSlotS(numChannels, dwellSlots);

    sweepLog = struct('slot', {}, 'observedChannel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

    for slotIndex = 1:numTimeSlots
        sweepLog = timeSlotS.run(slotIndex, UTs, SatelliteNode, apj, ServiceChannels, ControlChannels, targetBeamIndex, sweepLog);
    end

    hitVector = extractHitVector(sweepLog, totalSlots);
    [successRate, sinrDb, ackVector] = computeAttackUTMetrics(totalSlots);
    hitRate = mean(hitVector, 'omitnan') * 100;

    fprintf("  [Sweep]   JHR=%.2f%% | ACK=%.2f%% | SINR=%.3f dB\n", hitRate, successRate, sinrDb);
end



function [hitRate, successRate, sinrDb, hitVector, ackVector] = ...
    runComb(seed, totalSlots, fixedChannels)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    apj = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);

    timeSlotC = TimeSlotC(fixedChannels);

    combLog = struct('slot', {}, 'observedChannel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

    for slotIndex = 1:numTimeSlots
        combLog = timeSlotC.run(slotIndex, UTs, SatelliteNode, apj, ServiceChannels, ControlChannels, targetBeamIndex, combLog);
    end

    hitVector = extractHitVector(combLog, totalSlots);
    [successRate, sinrDb, ackVector] = computeAttackUTMetrics(totalSlots);
    hitRate = mean(hitVector, 'omitnan') * 100;

    fprintf("  [Comb]    JHR=%.2f%% | ACK=%.2f%% | SINR=%.3f dB\n", hitRate, successRate, sinrDb);
end



function [hitRate, successRate, sinrDb, hitVector, ackVector] = ...
    runShadowDQN(seed, totalSlots)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);

    timeSlotDE = TimeSlotDE(2, reconnaissanceDuration);
    timeSlotDE.EnableJamming = true;

    divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
        'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
        'observedChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'isAttackPhase', {}, 'jammingChannels', {});
    channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

    for slotIndex = 1:numTimeSlots
        [divergenceLog, channelLog] = timeSlotDE.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);
    end

    hitVector = extractHitVector(divergenceLog, totalSlots);
    [successRate, sinrDb, ackVector] = computeAttackUTMetrics(totalSlots);
    hitRate = mean(hitVector, 'omitnan') * 100;

    fprintf("  [APJ/ShadowDQN] JHR=%.2f%% | ACK=%.2f%% | SINR=%.3f dB\n", hitRate, successRate, sinrDb);
end



%% ================================================================
%  Extract per-slot hit / miss
% ================================================================

function hitVector = extractHitVector(logStruct, totalSlots)

    hitVector = nan(1, totalSlots);
    if isempty(logStruct)
        return;
    end

    for idx = 1:numel(logStruct)
        slot = logStruct(idx).slot;
        if slot < 1 || slot > totalSlots
            continue;
        end
        if ~logStruct(idx).isAttackPhase
            continue;
        end
        jc = logStruct(idx).jammingChannels;
        if isempty(jc)
            continue;
        end
        targetChannel = logStruct(idx).observedChannel;
        hitVector(slot) = double(any(targetChannel == jc));
    end
end



%% ================================================================
%  Extract Target UT metrics
% ================================================================

function [successRate, sinrDb, ackVector] = computeAttackUTMetrics(totalSlots)

    evalUTData = DebugHelper.TargetUTStorage('get', []);

    successRate = NaN;
    sinrDb = NaN;
    ackVector = nan(1, totalSlots);

    if isempty(evalUTData) || isempty(evalUTData.slots)
        return;
    end

    attackIdx = logical(evalUTData.isAttackPhase);

    if any(attackIdx)
        successRate = mean(evalUTData.isACK(attackIdx)) * 100;
        sinrDb = mean(evalUTData.SINR_dB(attackIdx), 'omitnan');
    end

    for i = 1:numel(evalUTData.slots)
        if ~evalUTData.isAttackPhase(i)
            continue;
        end
        slot = evalUTData.slots(i);
        if slot < 1 || slot > totalSlots
            continue;
        end
        ackVector(slot) = double(evalUTData.isACK(i));
    end
end



%% ================================================================
%  95% CI for aggregate results
% ================================================================

function ci = compute95CI(data)

    numMethods = size(data, 1);
    ci = nan(numMethods, 1);

    for i = 1:numMethods
        x = data(i, :);
        x = x(~isnan(x));
        n = numel(x);
        if n <= 1
            continue;
        end
        sem = std(x, 0) / sqrt(n);
        tCritical = tinv(0.975, n - 1);
        ci(i) = tCritical * sem;
    end
end



%% ================================================================
%  95% CI for time-series
% ================================================================

function ciSeries = computeTimeSeries95CI(data)

    [numMethods, ~, numSlots] = size(data);
    ciSeries = nan(numMethods, numSlots);

    for methodIndex = 1:numMethods
        for slotIndex = 1:numSlots
            x = squeeze(data(methodIndex, :, slotIndex));
            x = x(~isnan(x));
            n = numel(x);
            if n <= 1
                continue;
            end
            sem = std(x, 0) / sqrt(n);
            tCritical = tinv(0.975, n - 1);
            ciSeries(methodIndex, slotIndex) = tCritical * sem;
        end
    end
end



%% ================================================================
%  Reset DebugHelper
% ================================================================

function resetDebugStorage()
    DebugHelper.TargetUTStorage('reset', []);
end



%% ================================================================
%  Build Channels
% ================================================================

function [ServiceChannels, ControlChannels] = buildChannels()

    env;

    ServiceChannels = Channel.empty(0, numChannels);
    ControlChannels = Channel.empty(0, numChannels);

    for channelIndex = 1:numChannels
        centerFreq_Hz = serviceBandStart_Hz + (channelIndex - 0.5) * channelSpacing_Hz;
        serviceChannelStart_Hz = centerFreq_Hz - channelBandwidth_Hz / 2;
        serviceChannelEnd_Hz = centerFreq_Hz + channelBandwidth_Hz / 2;

        ServiceChannels(channelIndex) = Channel(channelIndex, ChannelType.Service, serviceChannelStart_Hz, serviceChannelEnd_Hz);
        ControlChannels(channelIndex) = Channel(channelIndex, ChannelType.Control, 1, 2);
    end
end



%% ================================================================
%  Build Network
% ================================================================

function [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork()

    env;

    satellitePosition = [0 0 satelliteAltitude];
    SatelliteNode = Satellite(9999, satellitePosition, numBeams);

    Beams = BeamFactory.createBeams(numBeams, maxBeamFootprintDiameter, beamRadius, beamSpacing, beamMaxGain_dBi, beam3dBWidth_deg, beamEIRPDensity_dBW_per_MHz, channelBandwidth_Hz);
    for beamIndex = 1:numBeams
        SatelliteNode.addBeam(Beams(beamIndex));
    end

    UTs = UTFactory.createUTs(Beams, numUTs);

    targetBeamIndex = find([Beams.AssociatedUTId] == targetUTId, 1);
    if isempty(targetBeamIndex)
        error("final3:TargetBeamNotFound", "targetUTId 에 연결된 Beam을 찾을 수 없습니다.");
    end
end