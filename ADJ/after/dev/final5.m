%% ==================== final5.m ====================
%  RQ5 (Optional Ablation): BC vs Shadow DQN Prediction Accuracy 비교
%  동일 seed/환경, 동일 Recon Duration에서 두 policy-imitation 방식이
%  Target policy 변화에 어떻게 다르게 반응하는지 비교 (Model-Class Comparison).
%  주의: 성능 저하가 관측돼도 "catastrophic forgetting"으로 단정하지 않음 —
%        과거 학습한 behavior에 대한 성능 손실까지 별도로 확인되지 않는 한
%        "reduced tracking capability / lower robustness to policy drift"로 서술.

clc; clear; clear variables; clear DebugHelper; close all;

seedTrial = 1;   % BC/Shadow DQN 동일 seed로 공정 비교

%% ==================== [실행 1] BC ====================
rng(seedTrial);
env;
[ServiceChannels, ControlChannels] = buildChannels();
[SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork(); %#ok<ASGLU>

APJNode = APJ_BCFactory.createAPJ_BC(UTs, Beams, targetUTId, targetJammerDistance);

timeSlot = TimeSlot();
bcLog = struct('slot', {}, 'observedChannel', {}, 'top1Channel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

for slotIndex = 1:numTimeSlots
    bcLog = timeSlot.run(slotIndex, UTs, SatelliteNode, APJNode, ServiceChannels, ControlChannels, bcLog);
end

evalPredData = DebugHelper.APJPredictionStorage('get', []);
bcSlots = evalPredData.slots;
bcTop1HitTrend = double(evalPredData.predicted == evalPredData.actual);
bcAttackStart = reconnaissanceDuration;

%% ==================== [실행 2] Shadow DQN (동일 seed/환경) ====================
rng(seedTrial);
env;
[ServiceChannels, ControlChannels] = buildChannels();
[SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);

timeSlotDE = TimeSlotDE(2);
divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
    'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
    'observedChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'isAttackPhase', {}, 'jammingChannels', {});
channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

for slotIndex = 1:numTimeSlots
    [divergenceLog, channelLog] = timeSlotDE.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);
end

dqnSlots = [divergenceLog.slot];
qB_matrix = vertcat(divergenceLog.qB);
dqnActual = [divergenceLog.observedChannel];
dqnTop1HitTrend = false(size(dqnSlots));
for idx = 1:numel(dqnSlots)
    [~, shadowRanking] = sort(qB_matrix(idx, :), 'descend');
    dqnTop1HitTrend(idx) = (dqnActual(idx) == shadowRanking(1));
end
dqnAttackStart = timeSlotDE.ReconnaissanceDuration;

%% ==================== 그래프: BC vs Shadow DQN Prediction Accuracy (Top-1) ====================
trendWindow = 100;
randomBaseline = 100 / numChannels;

figure;
plot(bcSlots, movmean(bcTop1HitTrend, trendWindow) * 100, 'LineWidth', 1.2, 'Color', [0.49 0.18 0.56]);
hold on;
plot(dqnSlots, movmean(dqnTop1HitTrend, trendWindow) * 100, 'LineWidth', 1.2, 'Color', [0 0.45 0.74]);
yline(randomBaseline, '--k', 'Random Baseline');
xline(bcAttackStart, '--r', 'Attack Start');
hold off;
legend("BC", "Shadow DQN (APJ)", "Location", "best");
xlabel("Time Slot"); ylabel("Top-1 Prediction Accuracy (%)");
title(sprintf("BC vs Shadow DQN: Channel Prediction Accuracy over Time (window=%d)", trendWindow));
ylim([0 100]); grid on;

%% ==================== 콘솔 요약 ====================
bcAttackIdx = bcSlots > bcAttackStart;
dqnAttackIdx = dqnSlots > dqnAttackStart;

fprintf("\n============================================================\n");
fprintf(" BC vs Shadow DQN — Attack 구간 Top-1 Prediction Accuracy\n");
fprintf("============================================================\n");
fprintf("BC          : %.2f%%\n", mean(bcTop1HitTrend(bcAttackIdx)) * 100);
fprintf("Shadow DQN  : %.2f%%\n", mean(dqnTop1HitTrend(dqnAttackIdx)) * 100);
fprintf("(주의: 이 결과만으로 'catastrophic forgetting' 여부를 단정하지 않음.\n");
fprintf(" 과거 학습한 채널 패턴에 대한 성능 손실까지 별도 검증이 필요함.)\n");
fprintf("============================================================\n");


%% ==================== Local Functions ====================

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
        error("final5:TargetBeamNotFound", "targetUTId 에 연결된 Beam을 찾을 수 없습니다.");
    end
    endf