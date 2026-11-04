%% ==================== final2.m ====================
% Attack Dynamics over Time — Data Generation (RQ3)
%
% "APJ의 높은 공격 효과가 실제로 채널 예측/재밍 적중에서 발생하는가?"
%
% 대표 1회 실행 대신, numTrials=5로 반복 실행 → trial 평균 + 95% CI shaded band
% (final3와 동일한 통계 처리 방식)
%
% 측정 지표:
%   ① Top-1 / Top-2 Prediction Accuracy over Time
%   ② Target UT ACK Rate over Time
%   ③ Target UT SINR over Time
%
% 이 스크립트는 시뮬레이션 실행 + raw 데이터 저장만 담당한다.
% 그래프는 final2_plot.m에서 저장된 .mat을 로드해서 그린다.

clc;
clear;
clear variables;
clear DebugHelper;
close all;

%% ================================================================
%  Configuration
% ================================================================

numTrials = 5;
baseSeed = 100;
trialSeeds = baseSeed + (0:numTrials-1);

movingWindow = 100;

env;
totalSlots = numTimeSlots;
reconDurationUsed = reconnaissanceDuration;
numCh = numChannels;

fprintf("\n============================================================\n");
fprintf(" Attack Dynamics over Time (APJ Shadow DQN)\n");
fprintf("============================================================\n");
fprintf(" Number of trials      : %d\n", numTrials);
fprintf(" Total slots           : %d\n", totalSlots);
fprintf(" Reconnaissance        : %d\n", reconDurationUsed);
fprintf(" Attack starts at      : %d\n", reconDurationUsed + 1);
fprintf(" Moving window         : %d slots\n", movingWindow);
fprintf("============================================================\n");


%% ================================================================
%  Result Storage
% ================================================================

top1Series = nan(numTrials, totalSlots);   % Top-1 prediction hit/miss
top2Series = nan(numTrials, totalSlots);   % Top-2 prediction hit/miss (=Attack구간 JHR과 동일)
ackSeries  = nan(numTrials, totalSlots);   % ACK/NACK
sinrSeries = nan(numTrials, totalSlots);   % SINR (dB)


%% ================================================================
%  Main Experiment
% ================================================================

for trial = 1:numTrials

    seed = trialSeeds(trial);

    fprintf("\n------------------------------------------------------------\n");
    fprintf(" Trial %d / %d (Seed=%d)\n", trial, numTrials, seed);
    fprintf("------------------------------------------------------------\n");

    [top1Series(trial,:), top2Series(trial,:), ackSeries(trial,:), sinrSeries(trial,:)] = ...
        runShadowDQNDynamics(seed, totalSlots);

end


%% ================================================================
%  Convert Slot-Level Results → Moving Average + 95% CI
% ================================================================

slots = 1:totalSlots;

top1Moving = nan(numTrials, totalSlots);
top2Moving = nan(numTrials, totalSlots);
ackMoving  = nan(numTrials, totalSlots);
sinrMoving = nan(numTrials, totalSlots);

for trial = 1:numTrials

    top1Moving(trial,:) = movingAvgPreserveNaN(top1Series(trial,:), movingWindow);
    top2Moving(trial,:) = movingAvgPreserveNaN(top2Series(trial,:), movingWindow);
    ackMoving(trial,:)  = movingAvgPreserveNaN(ackSeries(trial,:), movingWindow);
    sinrMoving(trial,:) = movingAvgPreserveNaN(sinrSeries(trial,:), movingWindow);

end

top1Moving = top1Moving * 100;
top2Moving = top2Moving * 100;
ackMoving  = ackMoving * 100;
% sinrMoving은 dB이므로 100 곱하지 않음

meanTop1Time = mean(top1Moving, 1, 'omitnan');
meanTop2Time = mean(top2Moving, 1, 'omitnan');
meanACKTime  = mean(ackMoving, 1, 'omitnan');
meanSINRTime = mean(sinrMoving, 1, 'omitnan');

ciTop1Time = computeTimeSeries95CI_1D(top1Moving);
ciTop2Time = computeTimeSeries95CI_1D(top2Moving);
ciACKTime  = computeTimeSeries95CI_1D(ackMoving);
ciSINRTime = computeTimeSeries95CI_1D(sinrMoving);


%% ================================================================
%  Overall Attack-Phase Summary (스칼라)
% ================================================================

attackIdx = slots > reconDurationUsed;

top1AttackMean = mean(top1Series(:, attackIdx), 2, 'omitnan') * 100;   % trial별
top2AttackMean = mean(top2Series(:, attackIdx), 2, 'omitnan') * 100;
ackAttackMean  = mean(ackSeries(:, attackIdx), 2, 'omitnan') * 100;
sinrAttackMean = mean(sinrSeries(:, attackIdx), 2, 'omitnan');

meanTop1 = mean(top1AttackMean, 'omitnan');  ciTop1 = compute95CI_1D(top1AttackMean);
meanTop2 = mean(top2AttackMean, 'omitnan');  ciTop2 = compute95CI_1D(top2AttackMean);
meanACK  = mean(ackAttackMean, 'omitnan');   ciACK  = compute95CI_1D(ackAttackMean);
meanSINR = mean(sinrAttackMean, 'omitnan');  ciSINR = compute95CI_1D(sinrAttackMean);

fprintf("\n============================================================\n");
fprintf(" Attack Phase Summary (mean over %d trials, 95%% CI)\n", numTrials);
fprintf("============================================================\n");
fprintf(" Top-1 Prediction Accuracy : %.2f%% ± %.2f\n", meanTop1, ciTop1);
fprintf(" Top-2 Prediction Accuracy : %.2f%% ± %.2f (=Jamming Hit Rate)\n", meanTop2, ciTop2);
fprintf(" Target ACK Success Rate   : %.2f%% ± %.2f\n", meanACK, ciACK);
fprintf(" Target SINR               : %.3f dB ± %.3f\n", meanSINR, ciSINR);
fprintf("============================================================\n");


%% ================================================================
%  SAVE ALL RESULTS
% ================================================================

save('final2_results.mat', ...
    'numTrials', 'movingWindow', 'totalSlots', 'reconDurationUsed', 'numCh', 'slots', ...
    'top1Series', 'top2Series', 'ackSeries', 'sinrSeries', ...
    'top1Moving', 'top2Moving', 'ackMoving', 'sinrMoving', ...
    'meanTop1Time', 'meanTop2Time', 'meanACKTime', 'meanSINRTime', ...
    'ciTop1Time', 'ciTop2Time', 'ciACKTime', 'ciSINRTime', ...
    'meanTop1', 'ciTop1', 'meanTop2', 'ciTop2', 'meanACK', 'ciACK', 'meanSINR', 'ciSINR', ...
    '-v7.3');

fprintf("\nNumerical results saved: final2_results.mat\n");
fprintf("그래프는 final2_plot.m을 실행해서 그리세요 (재시뮬레이션 불필요).\n");


%% ================================================================
%  Local Functions
% ================================================================

function [top1Vector, top2Vector, ackVector, sinrVector] = ...
    runShadowDQNDynamics(seed, totalSlots)

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

    [top1Vector, top2Vector] = extractPredictionVectors(divergenceLog, totalSlots);

    evalUTData = DebugHelper.TargetUTStorage('get', []);
    ackVector  = nan(1, totalSlots);
    sinrVector = nan(1, totalSlots);

    if ~isempty(evalUTData) && ~isempty(evalUTData.slots)
        for i = 1:numel(evalUTData.slots)
            slot = evalUTData.slots(i);
            if slot < 1 || slot > totalSlots
                continue;
            end
            ackVector(slot)  = double(evalUTData.isACK(i));
            sinrVector(slot) = evalUTData.SINR_dB(i);
        end
    end

    validTop2 = ~isnan(top2Vector);
    top2AttackHit = mean(top2Vector(validTop2), 'omitnan') * 100;
    fprintf("  [Seed=%d] Top-2 Attack-phase JHR = %.2f%%\n", seed, top2AttackHit);
end


%% ================================================================
%  Extract Top-1 / Top-2 prediction hit/miss (전체 구간, Recon 포함)
% ================================================================

function [top1Vector, top2Vector] = extractPredictionVectors(logStruct, totalSlots)

    top1Vector = nan(1, totalSlots);
    top2Vector = nan(1, totalSlots);

    if isempty(logStruct)
        return;
    end

    slotsArr = [logStruct.slot];
    observedChannels = [logStruct.observedChannel];
    qB_matrix = vertcat(logStruct.qB);

    for idx = 1:numel(logStruct)
        slot = slotsArr(idx);
        if slot < 1 || slot > totalSlots
            continue;
        end

        [~, shadowRanking] = sort(qB_matrix(idx, :), 'descend');
        observed = observedChannels(idx);

        top1Vector(slot) = double(observed == shadowRanking(1));
        top2Vector(slot) = double(any(observed == shadowRanking(1:min(2, numel(shadowRanking)))));
    end
end


%% ================================================================
%  Moving average that keeps leading/trailing NaN outside valid range
% ================================================================

function y = movingAvgPreserveNaN(x, windowSize)

    y = nan(size(x));
    validIdx = ~isnan(x);

    if ~any(validIdx)
        return;
    end

    firstValid = find(validIdx, 1, 'first');
    lastValid  = find(validIdx, 1, 'last');

    y(firstValid:lastValid) = movmean(x(firstValid:lastValid), windowSize, 'omitnan');
end


%% ================================================================
%  95% CI (time-series, 1 method only, N trials x N slots)
% ================================================================

function ciSeries = computeTimeSeries95CI_1D(data)

    [~, numSlots] = size(data);
    ciSeries = nan(1, numSlots);

    for slotIndex = 1:numSlots
        x = data(:, slotIndex);
        x = x(~isnan(x));
        n = numel(x);
        if n <= 1
            continue;
        end
        sem = std(x, 0) / sqrt(n);
        tCritical = tinv(0.975, n - 1);
        ciSeries(slotIndex) = tCritical * sem;
    end
end


%% ================================================================
%  95% CI (scalar, N trials)
% ================================================================

function ci = compute95CI_1D(data)

    x = data(~isnan(data));
    n = numel(x);
    ci = NaN;
    if n <= 1
        return;
    end
    sem = std(x, 0) / sqrt(n);
    tCritical = tinv(0.975, n - 1);
    ci = tCritical * sem;
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
        error("final2:TargetBeamNotFound", "targetUTId 에 연결된 Beam을 찾을 수 없습니다.");
    end
end