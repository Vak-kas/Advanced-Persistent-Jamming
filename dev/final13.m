%% ==================== final13.m ====================
% Target Beam Position Sweep — APJ with occupancy-unaware shadow DQN
%
% RQ3:
%   Target이 fixed decision order의 첫 번째가 아닐 때(preceding-beam
%   occupancy가 존재할 때), occupancy를 모르는 APJ(0벡터 입력)가
%   얼마나 성능을 유지하는가?
%
%   Target 위치 T = targetList (beam index = UT id).
%   Shadow DQN은 모든 T에서 occupancy 입력으로 0벡터를 사용(TimeSlotDE).
%   Target 자신은 실제 occupancy rho_T(t)를 사용 -> T가 클수록 shadow와
%   target의 입력 mismatch가 커진다.
%
% 전제:
%   - TimeSlotDE.m 이 shadow/prediction occupancy를 zeros로 두는 버전
%   - UT.m / ObservationManager.m 수정본 (관측에 재밍 포함, 전 UT 관측)
%
% 출력: final13_results.mat, 콘솔 요약, 그림 (JHR / ACK / PredAcc vs T)

clc;
clear;
clear variables;
clear DebugHelper;
close all;

%% ================================================================
%  Configuration
% ================================================================

targetList = [1 5 9 13 17];      % target beam index (= UT id)
numTargets = numel(targetList);

numTrials = 5;
baseSeed = 100;
trialSeeds = baseSeed + (0:numTrials-1);

runNoAttackReference = false;    % true면 각 T에 대해 No-Attack ACK도 측정 (실행 시간 2배)

env;
totalSlots = numTimeSlots;

% 병렬 풀 (툴박스 없으면 건너뜀)
if license('test', 'Distrib_Computing_Toolbox')
    if isempty(gcp('nocreate'))
        parpool('local', min(numTrials, feature('numcores')));
    end
    fprintf("Parallel pool: %d workers\n", gcp('nocreate').NumWorkers);
else
    fprintf("Parallel Computing Toolbox 없음 -> 순차 실행\n");
end
reconDurationUsed = reconnaissanceDuration;

fprintf("\n============================================================\n");
fprintf(" Target Beam Position Sweep (occupancy-unaware APJ)\n");
fprintf("============================================================\n");
fprintf(" Target list        : %s\n", mat2str(targetList));
fprintf(" Number of trials   : %d\n", numTrials);
fprintf(" Total slots        : %d (recon %d / attack %d)\n", totalSlots, reconDurationUsed, totalSlots - reconDurationUsed);
fprintf(" No-Attack ref      : %d\n", runNoAttackReference);
fprintf("============================================================\n");

%% ================================================================
%  Result Storage
% ================================================================

hitRateResults = nan(numTargets, numTrials);   % Top-2 JHR
predAccResults = nan(numTargets, numTrials);   % Top-1 prediction accuracy
successResults = nan(numTargets, numTrials);   % Target ACK (attack phase)
sinrResults    = nan(numTargets, numTrials);
baselineAck    = nan(numTargets, numTrials);   % No-Attack ACK (optional)

%% ================================================================
%  Main Experiment
% ================================================================

for ti = 1:numTargets
    T = targetList(ti);

    fprintf("\n############################################################\n");
    fprintf(" Target beam T = %d\n", T);
    fprintf("############################################################\n");

    % trial 병렬 실행 (Parallel Computing Toolbox 있으면 parfor, 없으면 for로 동작)
    % 각 trial은 rng(seed)로 시작하므로 순차/병렬 결과가 동일하다.
    hitRow  = nan(1, numTrials);
    accRow  = nan(1, numTrials);
    sucRow  = nan(1, numTrials);
    sinrRow = nan(1, numTrials);
    baseRow = nan(1, numTrials);

    parfor trial = 1:numTrials
        seed = trialSeeds(trial);

        [hitRow(trial), accRow(trial), sucRow(trial), sinrRow(trial)] = ...
            runShadowDQNTarget(seed, T, totalSlots, true);

        if runNoAttackReference
            [~, ~, baseRow(trial), ~] = runShadowDQNTarget(seed, T, totalSlots, false);
        end
    end

    hitRateResults(ti,:) = hitRow;
    predAccResults(ti,:) = accRow;
    successResults(ti,:) = sucRow;
    sinrResults(ti,:)    = sinrRow;
    baselineAck(ti,:)    = baseRow;
end

%% ================================================================
%  Aggregate
% ================================================================

meanHit = mean(hitRateResults, 2, 'omitnan');  stdHit = std(hitRateResults, 0, 2, 'omitnan');
meanAcc = mean(predAccResults, 2, 'omitnan');  stdAcc = std(predAccResults, 0, 2, 'omitnan');
meanSuc = mean(successResults, 2, 'omitnan');  stdSuc = std(successResults, 0, 2, 'omitnan');
meanBase = mean(baselineAck, 2, 'omitnan');

ciHit = compute95CI(hitRateResults);
ciAcc = compute95CI(predAccResults);
ciSuc = compute95CI(successResults);
ciBase = compute95CI(baselineAck);

fprintf("\n============================================================\n");
fprintf(" Target Position Sweep — Final Results\n");
fprintf("============================================================\n");
for ti = 1:numTargets
    fprintf("T=%2d : JHR %.2f%% ± %.2f | PredAcc %.2f%% ± %.2f | ACK %.2f%% ± %.2f", ...
        targetList(ti), meanHit(ti), stdHit(ti), meanAcc(ti), stdAcc(ti), meanSuc(ti), stdSuc(ti));
    if runNoAttackReference
        fprintf(" | NoAttack ACK %.2f%%", meanBase(ti));
    end
    fprintf("\n       95%% CI: JHR ± %.2f | PredAcc ± %.2f | ACK ± %.2f\n", ciHit(ti), ciAcc(ti), ciSuc(ti));
end
fprintf("============================================================\n");

%% ================================================================
%  Save
% ================================================================

save('final13_results.mat', ...
    'targetList', 'numTargets', 'numTrials', 'totalSlots', 'reconDurationUsed', ...
    'hitRateResults', 'predAccResults', 'successResults', 'sinrResults', 'baselineAck', ...
    'meanHit', 'stdHit', 'meanAcc', 'stdAcc', 'meanSuc', 'stdSuc', 'meanBase', ...
    'ciHit', 'ciAcc', 'ciSuc', 'ciBase', '-v7.3');
fprintf("\nSaved: final13_results.mat\n");

%% ================================================================
%  Plot
% ================================================================

figure('Color', 'w', 'Position', [100 100 850 430]);
hold on;
colorJHR = [0 0.45 0.74]; colorACK = [0.85 0.33 0.10]; colorAcc = [0.47 0.67 0.19];
offset = 0.15;
plot(targetList - offset, meanHit, '-', 'Color', colorJHR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
plot(targetList + offset, meanSuc, '-', 'Color', colorACK, 'LineWidth', 1.5, 'HandleVisibility', 'off');
plot(targetList, meanAcc, '-', 'Color', colorAcc, 'LineWidth', 1.5, 'HandleVisibility', 'off');
errorbar(targetList - offset, meanHit, ciHit, 'o', 'LineWidth', 1.5, 'MarkerSize', 7, 'CapSize', 8, 'Color', colorJHR, 'MarkerFaceColor', 'w');
errorbar(targetList + offset, meanSuc, ciSuc, 's', 'LineWidth', 1.5, 'MarkerSize', 7, 'CapSize', 8, 'Color', colorACK, 'MarkerFaceColor', 'w');
errorbar(targetList, meanAcc, ciAcc, '^', 'LineWidth', 1.5, 'MarkerSize', 7, 'CapSize', 8, 'Color', colorAcc, 'MarkerFaceColor', 'w');
yline(20, '--k', 'Random Top-2 (20%)', 'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');
if runNoAttackReference
    plot(targetList, meanBase, ':', 'Color', [0.4 0.4 0.4], 'LineWidth', 1.3, 'DisplayName', 'No-Attack ACK');
end
xlabel("Target Beam Index (decision order)");
ylabel("Rate (%)");
legend(["Jamming Hit Rate", "Target ACK Success Rate", "Top-1 Prediction Accuracy"], 'Location', 'best');
xticks(targetList);
xlim([min(targetList)-1, max(targetList)+1]);
ylim([0 100]);
grid on; box on;
hold off;

%% ================================================================
%  Local Functions
% ================================================================

function [hitRate, predAcc, successRate, sinrDb] = runShadowDQNTarget(seed, T, totalSlots, enableJamming)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    targetUTId = T;   %#ok<NASGU>  env 값 덮어쓰기 (아래에서 명시적으로 전달)

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork(T);

    apjd = APJFactory.createAPJ(UTs, Beams, T, targetJammerDistance);
    registerJammer(UTs, apjd, T, true);

    timeSlotDE = TimeSlotDE(2, reconnaissanceDuration);
    timeSlotDE.EnableJamming = enableJamming;
    timeSlotDE.Verbose = false;

    divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
        'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
        'observedChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'isAttackPhase', {}, 'jammingChannels', {});
    channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

    for slotIndex = 1:numTimeSlots
        [divergenceLog, channelLog] = timeSlotDE.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);
    end

    verifyObservation(UTs, totalSlots, sprintf("T=%d", T));

    [hitVector, top1Vector] = extractHitVectors(divergenceLog, totalSlots);
    [successRate, sinrDb] = computeAttackUTMetrics();

    hitRate = mean(hitVector, 'omitnan') * 100;
    predAcc = mean(top1Vector, 'omitnan') * 100;

    if enableJamming
        fprintf("  [T=%2d, Seed=%d] JHR=%.2f%% | PredAcc=%.2f%% | ACK=%.2f%% | SINR=%.3f dB\n", T, seed, hitRate, predAcc, successRate, sinrDb);
    else
        fprintf("  [T=%2d, Seed=%d, No-Attack] ACK=%.2f%%\n", T, seed, successRate);
    end
end

function registerJammer(UTs, jammer, targetUTId, selfObserve)
    for utIndex = 1:numel(UTs)
        UTs(utIndex).ObservationManager.Jammer = jammer;
    end
    if selfObserve
        jammer.ObservationManager.Jammer   = jammer;
        jammer.ObservationManager.TargetUT = UTs(targetUTId);
    end
    assert(~isempty(UTs(targetUTId).ObservationManager.Jammer), "final13:JammerNotRegistered");
end

function verifyObservation(UTs, totalSlots, label)
    numObs = arrayfun(@(u) u.ObservationManager.NumObservations, UTs);
    if any(numObs < totalSlots)
        warning("final13:ObservationMissing", "[%s] 일부 UT 관측 횟수 부족 (min=%d, expected>=%d).", label, min(numObs), totalSlots);
    end
end

function [hitVector, top1Vector] = extractHitVectors(logStruct, totalSlots)
    hitVector  = nan(1, totalSlots);
    top1Vector = nan(1, totalSlots);
    if isempty(logStruct), return; end
    qB_matrix = vertcat(logStruct.qB);
    for idx = 1:numel(logStruct)
        if ~logStruct(idx).isAttackPhase, continue; end
        slot = logStruct(idx).slot;
        if slot < 1 || slot > totalSlots, continue; end
        observed = logStruct(idx).observedChannel;
        jc = logStruct(idx).jammingChannels;
        if ~isempty(jc)
            hitVector(slot) = double(any(observed == jc));
        end
        [~, ranking] = sort(qB_matrix(idx, :), 'descend');
        top1Vector(slot) = double(observed == ranking(1));
    end
end

function [successRate, sinrDb] = computeAttackUTMetrics()
    evalUTData = DebugHelper.TargetUTStorage('get', []);
    successRate = NaN; sinrDb = NaN;
    if isempty(evalUTData) || isempty(evalUTData.slots), return; end
    attackIdx = logical(evalUTData.isAttackPhase);
    if any(attackIdx)
        successRate = mean(evalUTData.isACK(attackIdx)) * 100;
        sinrDb = mean(evalUTData.SINR_dB(attackIdx), 'omitnan');
    end
end

function ci = compute95CI(data)
    n0 = size(data, 1);
    ci = nan(n0, 1);
    for i = 1:n0
        x = data(i, :); x = x(~isnan(x)); n = numel(x);
        if n <= 1, continue; end
        ci(i) = tcrit975(n - 1) * std(x, 0) / sqrt(n);
    end
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
        serviceChannelStart_Hz = centerFreq_Hz - channelBandwidth_Hz / 2;
        serviceChannelEnd_Hz = centerFreq_Hz + channelBandwidth_Hz / 2;
        ServiceChannels(channelIndex) = Channel(channelIndex, ChannelType.Service, serviceChannelStart_Hz, serviceChannelEnd_Hz);
        ControlChannels(channelIndex) = Channel(channelIndex, ChannelType.Control, 1, 2);
    end
end

function [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork(T)
    env;
    satellitePosition = [0 0 satelliteAltitude];
    SatelliteNode = Satellite(9999, satellitePosition, numBeams);
    Beams = BeamFactory.createBeams(numBeams, maxBeamFootprintDiameter, beamRadius, beamSpacing, beamMaxGain_dBi, beam3dBWidth_deg, beamEIRPDensity_dBW_per_MHz, channelBandwidth_Hz);
    for beamIndex = 1:numBeams
        SatelliteNode.addBeam(Beams(beamIndex));
    end
    UTs = UTFactory.createUTs(Beams, numUTs);
    targetBeamIndex = find([Beams.AssociatedUTId] == T, 1);
    if isempty(targetBeamIndex)
        error("final13:TargetBeamNotFound", "targetUTId %d 에 연결된 Beam을 찾을 수 없습니다.", T);
    end
end