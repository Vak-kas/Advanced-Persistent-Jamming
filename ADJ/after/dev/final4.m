%% ==================== final4.m ====================
%  Attack Dynamics over Time (RQ3: 높은 공격 효과가 실제로 예측/JHR에서 발생하는가?)
%  대표 Shadow DQN 실행 1개. Attack 구간에서 JHR(Top-2) == PredictionAccuracy(Top-2)이므로
%  Prediction Accuracy 그래프 하나로 정찰 단계 학습 + 공격 단계 명중률을 함께 보여줌.

clc; clear; clear variables; clear DebugHelper; close all;

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

satellitePosition = [0 0 satelliteAltitude];
SatelliteNode = Satellite(9999, satellitePosition, numBeams);

Beams = BeamFactory.createBeams(numBeams, maxBeamFootprintDiameter, beamRadius, beamSpacing, beamMaxGain_dBi, beam3dBWidth_deg, beamEIRPDensity_dBW_per_MHz, channelBandwidth_Hz);
for beamIndex = 1:numBeams
    SatelliteNode.addBeam(Beams(beamIndex));
end

UTs = UTFactory.createUTs(Beams, numUTs);

targetBeamIndex = find([Beams.AssociatedUTId] == targetUTId, 1);
if isempty(targetBeamIndex)
    error("final4:TargetBeamNotFound", "targetUTId %d 에 연결된 Beam을 찾을 수 없습니다.", targetUTId);
end

apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);
targetUT = UTs(targetUTId);

fprintf("\n============================================================\n");
fprintf(" APJ (Shadow DQN) — Attack Dynamics 대표 실행\n");
fprintf("============================================================\n");
fprintf("Target UT               : UT%d\n", targetUT.Id);
fprintf("Num Time Slots           : %d\n", numTimeSlots);
fprintf("Reconnaissance Duration  : %d\n", reconnaissanceDuration);
fprintf("============================================================\n");

timeSlotDE = TimeSlotDE(2);

divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
    'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
    'observedChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'isAttackPhase', {}, 'jammingChannels', {});
channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

for slotIndex = 1:numTimeSlots
    [divergenceLog, channelLog] = timeSlotDE.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);
end

if isempty(divergenceLog)
    warning("final4:EmptyLog", "divergenceLog가 비어 있습니다."); return;
end

%% ==================== [그래프 A] Rolling Prediction Accuracy (Top-1/Top-2, 전체 구간) ====================
slots = [divergenceLog.slot];
qB_matrix = vertcat(divergenceLog.qB);
actualActions = [divergenceLog.observedChannel];
numCh = numel(ServiceChannels);
attackStartSlot = timeSlotDE.ReconnaissanceDuration;
trendWindow = min(100, numel(slots));

top1HitTrend = false(size(slots));
top2HitTrend = false(size(slots));
for idx = 1:numel(slots)
    [~, shadowRanking] = sort(qB_matrix(idx, :), 'descend');
    actualCh = actualActions(idx);
    top1HitTrend(idx) = (actualCh == shadowRanking(1));
    top2HitTrend(idx) = any(actualCh == shadowRanking(1:min(2, numel(shadowRanking))));
end

randomBaseline_Top1 = 100 / numCh;
randomBaseline_Top2 = 100 * min(2, numCh) / numCh;

figure;
plot(slots, movmean(top1HitTrend, trendWindow) * 100, 'LineWidth', 1.2, 'Color', [0.85 0.33 0.10]);
hold on;
plot(slots, movmean(top2HitTrend, trendWindow) * 100, 'LineWidth', 1.2, 'Color', [0 0.45 0.74]);
yline(randomBaseline_Top1, '--', 'Color', [0.5 0.5 0.5], 'Label', 'Random (Top-1)');
yline(randomBaseline_Top2, '--k', 'Random (Top-2)');
xline(attackStartSlot, '--r', 'Attack Start');
hold off;
legend("Top-1", "Top-2 (=Attack구간 JHR)", "Location", "best");
xlabel("Time Slot"); ylabel("Accuracy / Jamming Hit Rate (%)");
title(sprintf("APJ: Channel Prediction Accuracy over Time (window=%d)", trendWindow));
ylim([0 100]); grid on;

%% ==================== [그래프 B] Target UT ACK Rate / SINR over Time ====================
DebugHelper.printTargetUTSummary();
FigureHelper.plotTargetUTThroughput(100);

%% ==================== 콘솔 요약 ====================
attackIdx = find([divergenceLog.isAttackPhase]);
fprintf("\n============================================================\n");
fprintf(" Attack Dynamics 요약\n");
fprintf("============================================================\n");
fprintf("Attack 구간 Top-1 Accuracy : %.2f%%\n", mean(top1HitTrend(attackIdx)) * 100);
fprintf("Attack 구간 Top-2 Accuracy(=JHR) : %.2f%%\n", mean(top2HitTrend(attackIdx)) * 100);
fprintf("============================================================\n");