%% ==================== final1.m ====================
% Reconnaissance Duration Sweep — Data Generation + Plotting
%
% RQ2:
%   Reconnaissance가 실제로 APJ 성능에 기여하는가?
%   Recon Duration = {0, 500, 1000, 1500, 2000}
%
% Fixed Attack Evaluation Window = 1000 slots
%   (numTimeSlots = reconDuration + attackWindow, 공정 비교를 위해
%    모든 recon 조건에서 Attack 구간 길이를 동일하게 고정)
%
% [2026-09-30 수정]
%   - 재머 노드를 UT/APJ ObservationManager에 등록 (registerJammer).
%     등록하지 않으면 JAMMING 패킷이 RF 관측에서 제외됨.
%   - UT.performHARQ가 매 슬롯 observe()를 호출하도록 수정된 UT.m과 함께 사용.
%   - TimeSlotDE.Verbose = false (슬롯별 디버그 출력 끔).
%
% [2026-10-08 수정]
%   - numTrials 5 -> 10 (seed 100..109). 기존 5-trial 결과(seed 100..104)는
%     그대로 포함되므로 처음 5개 trial 값은 이전 결과와 동일.
%   - trial 루프를 parfor로 병렬화 (Parallel Computing Toolbox 있으면 자동,
%     없으면 일반 for로 동작). 각 trial은 rng(seed)로 시작하므로 결과 동일.

clc;
clear;
clear variables;
clear DebugHelper;
close all;


%% ================================================================
%  Configuration
% ================================================================

reconDurationList = [0, 500, 1000, 1500, 2000];
numReconConditions = numel(reconDurationList);

attackWindow = 1000;   % Fixed Attack Evaluation Window (elapsed attack time 1~1000)

% Final paper: >=5 recommended / Debug: 1~3
numTrials = 10;   % 20으로 올리려면 여기만 변경

baseSeed = 100;
trialSeeds = baseSeed + (0:numTrials-1);

% Moving-average window (final3와 동일 기준)
movingWindow = 100;

reconColors = lines(numReconConditions);

% 병렬 풀 (Parallel Computing Toolbox 없으면 건너뜀 -> parfor가 for로 동작)
if license('test', 'Distrib_Computing_Toolbox')
    if isempty(gcp('nocreate'))
        parpool('local', min(numTrials, feature('numcores')));
    end
    fprintf("Parallel pool: %d workers\n", gcp('nocreate').NumWorkers);
else
    fprintf("Parallel Computing Toolbox 없음 -> 순차 실행\n");
end


fprintf("\n============================================================\n");
fprintf(" Reconnaissance Duration Sweep\n");
fprintf(" [jamming INCLUDED in RF observation / all UTs observe]\n");
fprintf("============================================================\n");
fprintf(" Recon Duration list   : %s\n", mat2str(reconDurationList));
fprintf(" Attack Window (fixed) : %d slots\n", attackWindow);
fprintf(" Number of trials      : %d\n", numTrials);
fprintf(" Moving window         : %d slots\n", movingWindow);
fprintf("============================================================\n");


%% ================================================================
%  Result Storage
% ================================================================

hitRateResults  = nan(numReconConditions, numTrials);   % Top-2 JHR (attack구간 전체 평균, 스칼라)
predAccResults  = nan(numReconConditions, numTrials);   % Top-1 예측정확도 (attack구간 전체 평균, 스칼라)
successResults  = nan(numReconConditions, numTrials);   % Target Success Rate (attack구간 전체 평균, 스칼라)

% Elapsed Attack Time(1~attackWindow) 기준 slot-level 시계열
hitSeries  = nan(numReconConditions, numTrials, attackWindow);   % Top-2 hit/miss
ackSeries  = nan(numReconConditions, numTrials, attackWindow);   % ACK/NACK


%% ================================================================
%  Main Experiment
% ================================================================

for reconIdx = 1:numReconConditions

    reconDuration = reconDurationList(reconIdx);

    fprintf("\n");
    fprintf("############################################################\n");
    fprintf(" Recon Duration = %d\n", reconDuration);
    fprintf("############################################################\n");

    % trial 병렬 실행. parfor 슬라이싱 규칙 때문에 임시 변수에 모았다가 대입.
    hitRow  = nan(1, numTrials);
    accRow  = nan(1, numTrials);
    sucRow  = nan(1, numTrials);
    hitSer  = nan(numTrials, attackWindow);
    ackSer  = nan(numTrials, attackWindow);

    parfor trial = 1:numTrials
        [hitRow(trial), accRow(trial), sucRow(trial), hv, av] = ...
            runShadowDQNRecon(trialSeeds(trial), reconDuration, attackWindow);
        hitSer(trial, :) = hv;
        ackSer(trial, :) = av;
    end

    hitRateResults(reconIdx, :) = hitRow;
    predAccResults(reconIdx, :) = accRow;
    successResults(reconIdx, :) = sucRow;
    hitSeries(reconIdx, :, :)   = reshape(hitSer, 1, numTrials, attackWindow);
    ackSeries(reconIdx, :, :)   = reshape(ackSer, 1, numTrials, attackWindow);
end


%% ================================================================
%  Aggregate Statistics (요약 스칼라)
% ================================================================

meanHit = mean(hitRateResults, 2, 'omitnan');
stdHit  = std(hitRateResults, 0, 2, 'omitnan');

meanAcc = mean(predAccResults, 2, 'omitnan');
stdAcc  = std(predAccResults, 0, 2, 'omitnan');

meanSuc = mean(successResults, 2, 'omitnan');
stdSuc  = std(successResults, 0, 2, 'omitnan');

ciHit = compute95CI(hitRateResults);
ciAcc = compute95CI(predAccResults);
ciSuc = compute95CI(successResults);


fprintf("\n");
fprintf("============================================================\n");
fprintf(" Reconnaissance Duration Sweep — Final Results\n");
fprintf("============================================================\n");
for i = 1:numReconConditions
    fprintf( ...
        "Recon=%4d : JHR %.2f%% ± %.2f | PredAcc %.2f%% ± %.2f | Success %.2f%% ± %.2f\n", ...
        reconDurationList(i), meanHit(i), stdHit(i), meanAcc(i), stdAcc(i), meanSuc(i), stdSuc(i));
    fprintf( ...
        "            95%% CI:  JHR ± %.2f | PredAcc ± %.2f | Success ± %.2f\n", ...
        ciHit(i), ciAcc(i), ciSuc(i));
end
fprintf("============================================================\n");


%% ================================================================
%  Convert Slot-Level Binary Results → Moving Average (그래프용)
% ================================================================

elapsedAxis = 1:attackWindow;

hitMoving = nan(size(hitSeries));
ackMoving = nan(size(ackSeries));

for reconIdx = 1:numReconConditions
    for trial = 1:numTrials

        h = squeeze(hitSeries(reconIdx, trial, :))';
        a = squeeze(ackSeries(reconIdx, trial, :))';

        validHit = ~isnan(h);
        validACK = ~isnan(a);

        if any(validHit)
            firstHit = find(validHit, 1, 'first');
            lastHit  = find(validHit, 1, 'last');
            temp = movmean(h(firstHit:lastHit), movingWindow, 'omitnan');
            hitMoving(reconIdx, trial, firstHit:lastHit) = temp;
        end

        if any(validACK)
            firstACK = find(validACK, 1, 'first');
            lastACK  = find(validACK, 1, 'last');
            temp = movmean(a(firstACK:lastACK), movingWindow, 'omitnan');
            ackMoving(reconIdx, trial, firstACK:lastACK) = temp;
        end

    end
end

hitMoving = hitMoving * 100;
ackMoving = ackMoving * 100;

meanHitTime = squeeze(mean(hitMoving, 2, 'omitnan'));   % numReconConditions x attackWindow
meanACKTime = squeeze(mean(ackMoving, 2, 'omitnan'));

ciHitTime = computeTimeSeries95CI(hitMoving);
ciACKTime = computeTimeSeries95CI(ackMoving);


%% ================================================================
%  SAVE ALL RESULTS (재실행 없이 그래프만 다시 그릴 수 있도록)
% ================================================================

if ~isfolder('results'), mkdir('results'); end
save(sprintf('results/final1_results_%dtrials.mat', numTrials), ...
    'reconDurationList', 'numReconConditions', 'numTrials', 'movingWindow', ...
    'attackWindow', 'elapsedAxis', 'reconColors', ...
    'hitRateResults', 'predAccResults', 'successResults', ...
    'hitSeries', 'ackSeries', ...
    'hitMoving', 'ackMoving', ...
    'meanHit', 'stdHit', 'meanAcc', 'stdAcc', 'meanSuc', 'stdSuc', ...
    'ciHit', 'ciAcc', 'ciSuc', ...
    'meanHitTime', 'meanACKTime', 'ciHitTime', 'ciACKTime', ...
    '-v7.3');

fprintf("\nNumerical results saved: final1_results_%dtrials.mat\n", numTrials);


%% ================================================================
%  PLOTS
% ================================================================

legendLabels = arrayfun(@(d) sprintf("Recon = %d", d), reconDurationList, 'UniformOutput', false);

%% ---- (a) Jamming Hit Rate over Elapsed Attack Time ----
figure('Color', 'w', 'Position', [100 100 850 430]);
hold on;

for reconIdx = 1:numReconConditions
    m = meanHitTime(reconIdx, :);
    ci = ciHitTime(reconIdx, :);

    if all(isnan(m))
        continue;
    end

    validIdx = ~isnan(m) & ~isnan(ci);

    fill([elapsedAxis(validIdx), fliplr(elapsedAxis(validIdx))], ...
         [m(validIdx) + ci(validIdx), fliplr(m(validIdx) - ci(validIdx))], ...
         reconColors(reconIdx, :), 'FaceAlpha', 0.15, 'EdgeColor', 'none');

    plot(elapsedAxis, m, 'LineWidth', 1.8, 'Color', reconColors(reconIdx, :));
end

yline(20, '--k', 'Random Top-2 Baseline (20%)', 'LabelVerticalAlignment', 'bottom');

xlabel("Elapsed Attack Time (slots)");
ylabel("Jamming Hit Rate (%)");
title(sprintf("(a) Jamming Hit Rate over Time (%d-slot Moving Average)", movingWindow));
legend(legendLabels, 'Location', 'best');
ylim([0 100]);
xlim([1 attackWindow]);
grid on; box on;
hold off;


%% ---- (b) Target ACK Success Rate over Elapsed Attack Time ----
figure('Color', 'w', 'Position', [100 100 850 430]);
hold on;

for reconIdx = 1:numReconConditions
    m = meanACKTime(reconIdx, :);
    ci = ciACKTime(reconIdx, :);

    if all(isnan(m))
        continue;
    end

    validIdx = ~isnan(m) & ~isnan(ci);

    fill([elapsedAxis(validIdx), fliplr(elapsedAxis(validIdx))], ...
         [m(validIdx) + ci(validIdx), fliplr(m(validIdx) - ci(validIdx))], ...
         reconColors(reconIdx, :), 'FaceAlpha', 0.15, 'EdgeColor', 'none');

    plot(elapsedAxis, m, 'LineWidth', 1.8, 'Color', reconColors(reconIdx, :));
end

xlabel("Elapsed Attack Time (slots)");
ylabel("Target ACK Success Rate (%)");
title(sprintf("(b) Target ACK Success Rate over Time (%d-slot Moving Average)", movingWindow));
legend(legendLabels, 'Location', 'best');
ylim([0 100]);
xlim([1 attackWindow]);
grid on; box on;
hold off;


%% ---- (c) Overall Recon-Duration Summary (요약 errorbar) ----
figure('Color', 'w', 'Position', [100 100 850 430]);
hold on;

offset = 15;   % Recon 값이 로그가 아니라 선형이라 겹치지 않게 살짝 x 오프셋
errorbar(reconDurationList - offset, meanHit, ciHit, 'o', ...
    'LineWidth', 1.5, 'MarkerSize', 7, 'CapSize', 8, 'Color', [0 0.45 0.74]);
errorbar(reconDurationList + offset, meanSuc, ciSuc, 's', ...
    'LineWidth', 1.5, 'MarkerSize', 7, 'CapSize', 8, 'Color', [0.85 0.33 0.10]);

xlabel("Reconnaissance Duration (slots)");
ylabel("Rate (%)");
title("(c) Overall Attack-Phase Performance vs Reconnaissance Duration");
legend(["Jamming Hit Rate", "Target ACK Success Rate"], 'Location', 'best');
xticks(reconDurationList);
ylim([0 100]);
grid on; box on;
hold off;


%% ================================================================
%  Local Functions
% ================================================================


%% ----------------------------------------------------------------
%  [신규] 재머 등록 — final11.m과 동일
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
        "final1:JammerNotRegistered — Target UT에 재머 미등록");
end


%% ----------------------------------------------------------------
%  [신규] 관측이 실제로 수행됐는지 확인 — final11.m과 동일
% ----------------------------------------------------------------
function verifyObservation(UTs, totalSlots, label)

    numObs = arrayfun(@(u) u.ObservationManager.NumObservations, UTs);

    if any(numObs < totalSlots)
        warning("final1:ObservationMissing", ...
            "[%s] 일부 UT의 관측 횟수가 슬롯 수보다 적습니다 (min=%d, expected>=%d). " + ...
            "UT.performHARQ에 observe() 호출이 있는지 확인하세요.", ...
            label, min(numObs), totalSlots);
    end
end


function [hitRate, predAcc, successRate, hitVector, ackVector] = ...
    runShadowDQNRecon(seed, reconDuration, attackWindow)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    numTimeSlots = reconDuration + attackWindow;   % 공정 비교를 위해 Attack 구간 길이 고정

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);
    registerJammer(UTs, apjd, targetUTId, true);

    timeSlotDE = TimeSlotDE(2, reconDuration);
    timeSlotDE.EnableJamming = true;
    timeSlotDE.Verbose = false;

    divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
        'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
        'observedChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'isAttackPhase', {}, 'jammingChannels', {});
    channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

    for slotIndex = 1:numTimeSlots
        [divergenceLog, channelLog] = timeSlotDE.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);
    end

    verifyObservation(UTs, numTimeSlots, sprintf("Recon=%d", reconDuration));

    [hitVector, top1Vector] = extractHitVectors(divergenceLog, reconDuration, attackWindow);
    ackVector = extractACKVector(reconDuration, attackWindow);

    hitRate     = mean(hitVector, 'omitnan') * 100;
    predAcc     = mean(top1Vector, 'omitnan') * 100;
    successRate = mean(ackVector, 'omitnan') * 100;

    fprintf("  [Recon=%4d, Seed=%d] JHR(Top-2)=%.2f%% | PredAcc(Top-1)=%.2f%% | Success=%.2f%%\n", ...
        reconDuration, seed, hitRate, predAcc, successRate);
end


%% ================================================================
%  Extract per-slot Top-2 hit / Top-1 prediction accuracy
%  (Elapsed Attack Time = slot - reconDuration, 1~attackWindow)
% ================================================================

function [hitVector, top1Vector] = extractHitVectors(logStruct, reconDuration, attackWindow)

    hitVector  = nan(1, attackWindow);
    top1Vector = nan(1, attackWindow);

    if isempty(logStruct)
        return;
    end

    slots = [logStruct.slot];
    isAttackPhaseLog = [logStruct.isAttackPhase];
    observedChannels = [logStruct.observedChannel];
    qB_matrix = vertcat(logStruct.qB);

    attackIdx = find(isAttackPhaseLog);

    for idx = attackIdx
        elapsedTime = slots(idx) - reconDuration;
        if elapsedTime < 1 || elapsedTime > attackWindow
            continue;
        end

        jc = logStruct(idx).jammingChannels;
        observed = observedChannels(idx);

        if ~isempty(jc)
            hitVector(elapsedTime) = double(any(observed == jc));
        end

        [~, shadowRanking] = sort(qB_matrix(idx, :), 'descend');
        top1Vector(elapsedTime) = double(observed == shadowRanking(1));
    end
end


%% ================================================================
%  Extract Target UT ACK vector (Elapsed Attack Time 기준)
% ================================================================

function ackVector = extractACKVector(reconDuration, attackWindow)

    ackVector = nan(1, attackWindow);

    evalUTData = DebugHelper.TargetUTStorage('get', []);

    if isempty(evalUTData) || isempty(evalUTData.slots)
        return;
    end

    for i = 1:numel(evalUTData.slots)
        if ~evalUTData.isAttackPhase(i)
            continue;
        end
        elapsedTime = evalUTData.slots(i) - reconDuration;
        if elapsedTime < 1 || elapsedTime > attackWindow
            continue;
        end
        ackVector(elapsedTime) = double(evalUTData.isACK(i));
    end
end


%% ================================================================
%  95% CI for aggregate results (scalar, per condition)
% ================================================================

function ci = compute95CI(data)

    numConditions = size(data, 1);
    ci = nan(numConditions, 1);

    for i = 1:numConditions
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
%  95% CI for time-series (per condition, per elapsed-time slot)
% ================================================================

function ciSeries = computeTimeSeries95CI(data)

    [numConditions, ~, numSlots] = size(data);
    ciSeries = nan(numConditions, numSlots);

    for condIndex = 1:numConditions
        for slotIndex = 1:numSlots
            x = squeeze(data(condIndex, :, slotIndex));
            x = x(~isnan(x));
            n = numel(x);
            if n <= 1
                continue;
            end
            sem = std(x, 0) / sqrt(n);
            tCritical = tcrit975(n - 1);
            ciSeries(condIndex, slotIndex) = tCritical * sem;
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
        error("final1:TargetBeamNotFound", "targetUTId 에 연결된 Beam을 찾을 수 없습니다.");
    end
end