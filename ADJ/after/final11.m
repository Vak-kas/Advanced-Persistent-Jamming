%% ==================== final11.m ====================
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

techniqueNames = [
    "Random"
    "Sweep"
    "Comb"
    "DQN-IJ (Pretrained)"
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
fprintf(" Attack Method Comparison (with DQN-IJ)\n");
fprintf(" [jamming INCLUDED in RF observation / all UTs observe]\n");
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


    %% 1. Random
    [ ...
        hitRateResults(1,trial), ...
        successResults(1,trial), ...
        sinrResults(1,trial), ...
        hitSeries(1,trial,:), ...
        ackSeries(1,trial,:) ...
    ] = runRandom(seed, totalSlots);


    %% 2. Sweep
    [ ...
        hitRateResults(2,trial), ...
        successResults(2,trial), ...
        sinrResults(2,trial), ...
        hitSeries(2,trial,:), ...
        ackSeries(2,trial,:) ...
    ] = runSweep(seed, totalSlots);


    %% 3. Comb
    [ ...
        hitRateResults(3,trial), ...
        successResults(3,trial), ...
        sinrResults(3,trial), ...
        hitSeries(3,trial,:), ...
        ackSeries(3,trial,:) ...
    ] = runComb(seed, totalSlots, combFixedChannels);


    %% 4. DQN-IJ (Pretrained, dry-run recon = IJ2)
    [ ...
        hitRateResults(4,trial), ...
        successResults(4,trial), ...
        sinrResults(4,trial), ...
        hitSeries(4,trial,:), ...
        ackSeries(4,trial,:) ...
    ] = runIJ(seed, totalSlots);


    %% 5. APJ Shadow DQN
    [ ...
        hitRateResults(5,trial), ...
        successResults(5,trial), ...
        sinrResults(5,trial), ...
        hitSeries(5,trial,:), ...
        ackSeries(5,trial,:) ...
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
save('results/final11_results.mat', ...
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
fprintf("  final11_results.mat\n");
fprintf("그래프는 final11_plot.m을 실행해서 그리세요 (재시뮬레이션 불필요).\n");


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


function [ackRate, ackVector] = runNoAttack(seed, totalSlots)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);
    registerJammer(UTs, apjd, targetUTId, true);

    timeSlotDE = TimeSlotDE(2, reconnaissanceDuration);
    timeSlotDE.EnableJamming = false;
    timeSlotDE.Verbose = false;

    divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
        'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
        'observedChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'isAttackPhase', {}, 'jammingChannels', {});
    channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

    for slotIndex = 1:numTimeSlots
        [divergenceLog, channelLog] = timeSlotDE.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);
    end

    verifyObservation(UTs, totalSlots, "No-Attack");

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
    registerJammer(UTs, apj, targetUTId, false);

    topKJam = 2;
    timeSlotR = TimeSlotR(topKJam);

    rLog = struct('slot', {}, 'observedChannel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

    for slotIndex = 1:numTimeSlots
        rLog = timeSlotR.run(slotIndex, UTs, SatelliteNode, apj, ServiceChannels, ControlChannels, targetBeamIndex, rLog);
    end

    verifyObservation(UTs, totalSlots, "Random");

    hitVector = extractHitVectorGeneric(rLog, totalSlots, 'jammingChannels', 'observedChannel');
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
    registerJammer(UTs, apj, targetUTId, false);

    dwellSlots = 1;
    timeSlotS = TimeSlotS(numChannels, dwellSlots);

    sweepLog = struct('slot', {}, 'observedChannel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

    for slotIndex = 1:numTimeSlots
        sweepLog = timeSlotS.run(slotIndex, UTs, SatelliteNode, apj, ServiceChannels, ControlChannels, targetBeamIndex, sweepLog);
    end

    verifyObservation(UTs, totalSlots, "Sweep");

    hitVector = extractHitVectorGeneric(sweepLog, totalSlots, 'jammingChannels', 'observedChannel');
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
    registerJammer(UTs, apj, targetUTId, false);

    timeSlotC = TimeSlotC(fixedChannels);

    combLog = struct('slot', {}, 'observedChannel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

    for slotIndex = 1:numTimeSlots
        combLog = timeSlotC.run(slotIndex, UTs, SatelliteNode, apj, ServiceChannels, ControlChannels, targetBeamIndex, combLog);
    end

    verifyObservation(UTs, totalSlots, "Comb");

    hitVector = extractHitVectorGeneric(combLog, totalSlots, 'jammingChannels', 'observedChannel');
    [successRate, sinrDb, ackVector] = computeAttackUTMetrics(totalSlots);
    hitRate = mean(hitVector, 'omitnan') * 100;

    fprintf("  [Comb]    JHR=%.2f%% | ACK=%.2f%% | SINR=%.3f dB\n", hitRate, successRate, sinrDb);
end


function [hitRate, successRate, sinrDb, hitVector, ackVector] = ...
    runIJ(seed, totalSlots)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    ij = IntelligentJammerFactory.createIntelligentJammer(UTs, Beams, targetUTId, targetJammerDistance);
    registerJammer(UTs, ij, targetUTId, true);

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


function [hitRate, successRate, sinrDb, hitVector, ackVector] = ...
    runShadowDQN(seed, totalSlots)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);
    registerJammer(UTs, apjd, targetUTId, true);

    timeSlotDE = TimeSlotDE(2, reconnaissanceDuration);
    timeSlotDE.EnableJamming = true;
    timeSlotDE.Verbose = false;

    divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
        'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
        'observedChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'isAttackPhase', {}, 'jammingChannels', {});
    channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

    for slotIndex = 1:numTimeSlots
        [divergenceLog, channelLog] = timeSlotDE.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);
    end

    verifyObservation(UTs, totalSlots, "APJ");

    hitVector = extractHitVectorGeneric(divergenceLog, totalSlots, 'jammingChannels', 'observedChannel');
    [successRate, sinrDb, ackVector] = computeAttackUTMetrics(totalSlots);
    hitRate = mean(hitVector, 'omitnan') * 100;

    fprintf("  [APJ/ShadowDQN] JHR=%.2f%% | ACK=%.2f%% | SINR=%.3f dB\n", hitRate, successRate, sinrDb);
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
        error("final11:TargetBeamNotFound", "targetUTId 에 연결된 Beam을 찾을 수 없습니다.");
    end
end