%% ==================== final12.m ====================
% DQN-IJ (Phi=10, 자기 재밍 미관측 — Jing2025 충실) 재실행.
% final11_results_paper.mat을 로드해서 DQN-IJ(4번 행)만 교체하고
% final12_results.mat으로 저장. 원본 mat은 건드리지 않음.
%
% 전제: IntelligentJammer.m / IntelligentJammerAgent.m 이 phi(=env) 버전으로 교체돼 있어야 함.
% 나머지 방법(No-Attack / Random / Sweep / Comb / APJ)은 기존 결과 유지.
%
% 사용법:
%   1) final11_results_paper.mat 이 작업 폴더에 있어야 함
%   2) IJ_SELF_OBSERVE = false (Jing2025 슬롯 구조: 재밍 후 센싱 -> 자기 재밍은 state에 없음)
%   3) Phi는 env의 phi(=10)를 IntelligentJammer/Agent가 그대로 사용
%   4) 실행 -> final12_results.mat 생성 (final11_results_paper.mat 은 그대로)
%
% Attack Method Comparison — Data Generation (IJ 포함)
%
% RQ1:
%   Under the SAME attack start time and SAME attack budget,
%   which jamming method is most effective?
%
% Methods:
%   1) Random
%   2) Sweep
%   3) Comb (Fixed-Channel)
%   4) DQN-IJ (Pretrained)   <- Jing et al. 스타일 직접 정책 학습.
%      정찰 기간(1~T_R) 동안 Dry-run으로 미리 학습(재밍 패킷은 주입 안 함,
%      counterfactual SINR 추정 reward로 학습) -> APJ와 동일하게
%      "정찰 예산을 준비에 쓴다"는 조건을 맞춘 버전(=IJ2).
%   5) APJ (Shadow DQN)
%
%   + No-Attack baseline
%
% [2026-09-30 수정]
%   - 모든 run*에서 재머 노드를 UT/재머 ObservationManager에 등록
%     (registerJammer). 등록하지 않으면 JAMMING 패킷이 RF 관측에서 제외됨.
%   - UT.performHARQ가 매 슬롯 observe()를 호출하도록 수정된 UT.m과 함께 사용.
%   - TimeSlotDE.Verbose = false (슬롯별 디버그 출력 끔).
%
% 이 스크립트는 시뮬레이션 실행 + raw 데이터 저장만 담당한다.
% 그래프는 final11_plot.m에서 저장된 .mat을 로드해서 그린다.

clc;
clear;
clear variables;
clear DebugHelper;
close all;

%% ================================================================
%  Configuration
% ================================================================

% DQN-IJ 자기 재밍 관측 여부
%   false : Jing2025 Fig.2 (Jamming -> Sensing 순서)에 충실 — 자기 재밍은 state에 안 들어감
%   true  : APJ와 동일하게 target 거리 기준 자기 재밍 추정치를 state에 포함
IJ_SELF_OBSERVE = false;

resultsFile = 'results/final11_results_paper.mat';   % 원본 (final11.m 출력, IJ phi=1 / self-observe) — 수정하지 않음

assert(isfile(resultsFile), "final12:MissingResults — %s 가 없습니다.", resultsFile);

load(resultsFile);   % techniqueNames, numTrials, movingWindow, totalSlots, ...
                     % hitRateResults, successResults, sinrResults, hitSeries, ackSeries,
                     % baselineAckResults, baselineAckSeries 등

ijRow = find(techniqueNames == "DQN-IJ (Pretrained)", 1);
assert(~isempty(ijRow), "final11_rerunIJ:IJRowNotFound");

baseSeed = 100;
trialSeeds = baseSeed + (0:numTrials-1);

env;

fprintf("\n============================================================\n");
fprintf(" DQN-IJ RERUN ONLY (row %d) — Phi=%d, IJ_SELF_OBSERVE = %d\n", ijRow, phi, IJ_SELF_OBSERVE);
fprintf("============================================================\n");
fprintf(" Number of trials      : %d\n", numTrials);
fprintf(" Total slots           : %d\n", totalSlots);
fprintf(" Reconnaissance        : %d\n", reconDurationUsed);
fprintf("============================================================\n");


%% ================================================================
%  DQN-IJ 재실행 (4번 행만 덮어쓰기)
% ================================================================

for trial = 1:numTrials

    seed = trialSeeds(trial);

    fprintf("\n############################################################\n");
    fprintf(" [DQN-IJ rerun] Trial %d / %d (Seed=%d)\n", trial, numTrials, seed);
    fprintf("############################################################\n");

    [ ...
        hitRateResults(ijRow,trial), ...
        successResults(ijRow,trial), ...
        sinrResults(ijRow,trial), ...
        hitSeries(ijRow,trial,:), ...
        ackSeries(ijRow,trial,:) ...
    ] = runIJ(seed, totalSlots, IJ_SELF_OBSERVE);

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

fprintf("%-22s : ACK %.2f%% ± %.2f (95%% CI ± %.2f)\n", ...
    "No-Attack", baselineMeanACK, baselineStdACK, baselineCiACK);

for i = 1:numTechniques

    fprintf( ...
        "%-22s : JHR %.2f%% ± %.2f | ACK %.2f%% ± %.2f | SINR %.3f dB ± %.3f\n", ...
        techniqueNames(i), ...
        meanHit(i), stdHit(i), ...
        meanSuc(i), stdSuc(i), ...
        meanSinr(i), stdSinr(i));

    fprintf( ...
        "%-22s   JHR 95%% CI ± %.2f | ACK 95%% CI ± %.2f\n", ...
        "", ciHit(i), ciSuc(i));

end

fprintf("============================================================\n");


%% ================================================================
%  Convert Slot-Level Binary Results → Moving Average
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
            temp = movmean(h(firstHit:lastHit), movingWindow, 'omitnan');
            hitMoving(techniqueIndex, trial, firstHit:lastHit) = temp;
        end

        if any(validACK)
            firstACK = find(validACK, 1, 'first');
            lastACK  = find(validACK, 1, 'last');
            temp = movmean(a(firstACK:lastACK), movingWindow, 'omitnan');
            ackMoving(techniqueIndex, trial, firstACK:lastACK) = temp;
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
%  No-Attack Baseline Moving Average
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
%  SAVE ALL RESULTS
% ================================================================

if ~isfolder('results'), mkdir('results'); end
save('results/final12_results.mat', ...
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
fprintf("  results/final12_results.mat (DQN-IJ row updated, Phi=%d)\n", phi);
fprintf("그래프: final12_plot.m 실행 (Fig. 2 / Fig. 3).\n");


%% ================================================================
%  Local Functions
% ================================================================


%% ----------------------------------------------------------------
%  [신규] 재머 등록
%
%  모든 UT의 ObservationManager에 재머 노드를 등록해서 JAMMING 패킷의
%  수신 전력(재머 -> UT 거리 기준)이 RF 관측에 포함되게 한다.
%  재머 자신도 관측을 수행하는 경우(APJ / IJ)에는 자기 재밍을
%  Target UT 위치 기준으로 추정해 넣기 위해 selfObserve=true로 호출.
% ----------------------------------------------------------------
function registerJammer(UTs, jammer, targetUTId, selfObserve)

    for utIndex = 1:numel(UTs)
        UTs(utIndex).ObservationManager.Jammer = jammer;
    end

    if selfObserve
        jammer.ObservationManager.Jammer   = jammer;
        jammer.ObservationManager.TargetUT = UTs(targetUTId);
    end

    assert(~isempty(UTs(targetUTId).ObservationManager.Jammer), ...
        "final11:JammerNotRegistered — Target UT에 재머 미등록");
end


%% ----------------------------------------------------------------
%  [신규] 관측이 실제로 수행됐는지 확인 (UT.performHARQ 수정 여부 검증)
% ----------------------------------------------------------------
function verifyObservation(UTs, totalSlots, label)

    numObs = arrayfun(@(u) u.ObservationManager.NumObservations, UTs);

    if any(numObs < totalSlots)
        warning("final11:ObservationMissing", ...
            "[%s] 일부 UT의 관측 횟수가 슬롯 수보다 적습니다 (min=%d, expected>=%d). " + ...
            "UT.performHARQ에 observe() 호출이 있는지 확인하세요.", ...
            label, min(numObs), totalSlots);
    end
end






function [hitRate, successRate, sinrDb, hitVector, ackVector] = ...
    runIJ(seed, totalSlots, selfObserve)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    ij = IntelligentJammerFactory.createIntelligentJammer(UTs, Beams, targetUTId, targetJammerDistance);
    registerJammer(UTs, ij, targetUTId, selfObserve);

    timeSlotIJ = TimeSlotIJ(reconnaissanceDuration);
    timeSlotIJ.DryRun = true;    % IJ2: 정찰 예산을 dry-run 사전학습에 사용 (APJ와 동일 조건)
    timeSlotIJ.EnableJamming = true;
    timeSlotIJ.Verbose = false;

    ijLog = struct('slot', {}, 'isAttackPhase', {}, 'dryRunActive', {}, 'lossIJ', {}, ...
        'jammedChannels', {}, 'selectedChannels', {}, 'nextJamChannels', {}, ...
        'targetChannel', {}, 'targetHit', {}, 'targetACK', {}, 'targetSINR_dB', {}, ...
        'rewardIJ', {}, 'epsilonIJ', {}, 'selectionMethod', {}, 'qValuesIJ', {});
    channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

    for slotIndex = 1:numTimeSlots
        [ijLog, channelLog] = timeSlotIJ.run(slotIndex, UTs, SatelliteNode, ij, ServiceChannels, ControlChannels, targetBeamIndex, ijLog, channelLog);
    end

    verifyObservation(UTs, totalSlots, "DQN-IJ");

    hitVector = extractHitVectorGeneric(ijLog, totalSlots, 'jammedChannels', 'targetChannel');
    [successRate, sinrDb, ackVector] = computeAttackUTMetrics(totalSlots);
    hitRate = mean(hitVector, 'omitnan') * 100;

    fprintf("  [DQN-IJ]  JHR=%.2f%% | ACK=%.2f%% | SINR=%.3f dB\n", hitRate, successRate, sinrDb);
end



%% ================================================================
%  Extract per-slot hit / miss (generic — 필드명이 기법마다 달라서 인자로 받음)
% ================================================================

function hitVector = extractHitVectorGeneric(logStruct, totalSlots, jammedField, targetField)

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
        jc = logStruct(idx).(jammedField);
        if isempty(jc)
            continue;
        end
        targetChannel = logStruct(idx).(targetField);
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
        tCritical = tcrit975(n - 1);
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
            tCritical = tcrit975(n - 1);
            ciSeries(methodIndex, slotIndex) = tCritical * sem;
        end
    end
end


%% ================================================================
%  t 분포 97.5% 분위수 (Statistics Toolbox 없이 사용)
%  df = 1..30 lookup, 그 이상은 정규근사 1.96
%  (tinv(0.975, df)와 동일한 값)
% ================================================================

function t = tcrit975(df)
    table = [12.706 4.303 3.182 2.776 2.571 2.447 2.365 2.306 2.262 2.228 ...
             2.201 2.179 2.160 2.145 2.131 2.120 2.110 2.101 2.093 2.086 ...
             2.080 2.074 2.069 2.064 2.060 2.056 2.052 2.048 2.045 2.042];
    if df < 1
        t = NaN;
    elseif df <= numel(table)
        t = table(df);
    else
        t = 1.96;
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
        error("final11:TargetBeamNotFound", "targetUTId 에 연결된 Beam을 찾을 수 없습니다.");
    end
end