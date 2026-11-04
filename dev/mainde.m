clc; clear; clear variables; clear DebugHelper; close all;

%% ==================== Environment Settings ====================
env;

%% ==================== 채널 생성 ====================
ServiceChannels = Channel.empty(0, numChannels);
ControlChannels = Channel.empty(0, numChannels);
for channelIndex = 1:numChannels
    centerFreq_Hz = serviceBandStart_Hz + (channelIndex - 0.5) * channelSpacing_Hz;
    serviceChannelStart_Hz = centerFreq_Hz - channelBandwidth_Hz / 2;
    serviceChannelEnd_Hz = centerFreq_Hz + channelBandwidth_Hz / 2;
    ServiceChannels(channelIndex) = Channel(channelIndex, ChannelType.Service, serviceChannelStart_Hz, serviceChannelEnd_Hz);
    ControlChannels(channelIndex) = Channel(channelIndex, ChannelType.Control, 1, 2);
end

%% ==================== Satellite / Beam / UT 생성 ====================
satellitePosition = [0 0 satelliteAltitude];
SatelliteNode = Satellite(9999, satellitePosition, numBeams);

Beams = BeamFactory.createBeams(numBeams, maxBeamFootprintDiameter, beamRadius, beamSpacing, beamMaxGain_dBi, beam3dBWidth_deg, beamEIRPDensity_dBW_per_MHz, channelBandwidth_Hz);
for beamIndex = 1:numBeams
    SatelliteNode.addBeam(Beams(beamIndex));
end

UTs = UTFactory.createUTs(Beams, numUTs);

%% ==================== Target Beam 찾기 ====================
targetBeamIndex = find([Beams.AssociatedUTId] == targetUTId, 1);
if isempty(targetBeamIndex)
    error("mainDE:TargetBeamNotFound", "targetUTId %d 에 연결된 Beam을 찾을 수 없습니다.", targetUTId);
end
targetBeam = Beams(targetBeamIndex);

%% ==================== APJ 생성 ====================
apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);
targetUT = UTs(targetUTId);

%% ==================== [신규] 재머 등록 (관측에 재밍 포함) ====================
% ObservationManager가 JAMMING 패킷의 수신 전력을 계산하려면 재머 노드
% (위치/송신전력/이득)를 알아야 한다. 등록하지 않으면 기존처럼 재밍이
% 관측에서 제외된다.
%   - 모든 UT      : 재머 -> UT 거리 기준 실제 수신 전력
%   - APJ 자기 자신: APJ -> Target UT 거리 기준 (Target UT가 받을 전력 추정)
for utIndex = 1:numel(UTs)
    UTs(utIndex).ObservationManager.Jammer = apjd;
end
apjd.ObservationManager.Jammer   = apjd;
apjd.ObservationManager.TargetUT = targetUT;

assert(~isempty(targetUT.ObservationManager.Jammer), "mainDE:JammerNotRegistered — Jammer 미등록");
assert(~isempty(apjd.ObservationManager.TargetUT),   "mainDE:TargetUTNotRegistered — APJ TargetUT 미등록");

fprintf("\n============================================================\n");
fprintf(" RF-Observation + Oracle Action/Occupancy + SINR-Estimated Reward\n");
fprintf(" (TimeSlotDE) — jamming INCLUDED in RF observation\n");
fprintf("============================================================\n");
fprintf("Target UT         : UT%d\n", targetUT.Id);
fprintf("Target Beam       : Beam%d\n", targetBeamIndex);
fprintf("Target UT 위치    : (%.3f, %.3f) km\n", targetUT.Position(1) / 1e3, targetUT.Position(2) / 1e3);
fprintf("APJ 위치         : (%.3f, %.3f) km\n", apjd.Position(1) / 1e3, apjd.Position(2) / 1e3);
fprintf("Target-APJ 거리  : %.3f km\n", targetUT.distanceTo(apjd) / 1e3);
fprintf("Num Beams         : %d\n", numel(Beams));
fprintf("Num Channels      : %d\n", numChannels);
fprintf("Num Time Slots    : %d\n", numTimeSlots);
fprintf("Batch Size Target : %d\n", targetBeam.Agent.BatchSize);
fprintf("Batch Size Shadow : %d\n", apjd.Agent.BatchSize);
fprintf("APJ SINR Threshold : %.2f dB\n", apjd.SINRThreshold_dB);
fprintf("============================================================\n");

%% ==================== TimeSlotDE 생성 / 로그 초기화 ====================
% TimeSlotDE(topKJam): 1 = Top-1 채널만 재밍, 2 = Top-1+Top-2 동시 재밍(기본값)
timeSlotDE = TimeSlotDE(2, reconnaissanceDuration);

divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
    'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
    'observedChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'isAttackPhase', {}, 'jammingChannels', {});

channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

%% ==================== Time Slot 루프 ====================
% 관측에 재밍이 실제로 들어가는지 확인용: 공격 시작 직후 몇 슬롯의
% Target UT / APJ raw observation(dBm)을 출력. 재밍 채널은 약 -43 dBm,
% 나머지는 -120 ~ -90 dBm 근처여야 정상.
observationCheckSlots = reconnaissanceDuration + (1:3);

for slotIndex = 1:numTimeSlots
    [divergenceLog, channelLog] = timeSlotDE.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);

    if any(slotIndex == observationCheckSlots)
        fprintf("\n[OBS CHECK] slot %d | jamming ch = %s\n", slotIndex, mat2str(divergenceLog(end).jammingChannels));
        fprintf("  Target UT obs (dBm): %s\n", mat2str(round(targetUT.ObservationManager.CurrentObservation, 1)));
        fprintf("  APJ      obs (dBm): %s\n", mat2str(round(apjd.ObservationManager.CurrentObservation, 1)));
    end
end

if isempty(divergenceLog)
    warning("mainDE:EmptyDivergenceLog", "divergenceLog가 비어 있습니다."); return;
end
if isempty(channelLog)
    warning("mainDE:EmptyChannelLog", "channelLog가 비어 있습니다."); return;
end

%% ==================== 기본 데이터 추출 ====================
slots = [divergenceLog.slot];
qB_matrix = vertcat(divergenceLog.qB);
actualActions = [divergenceLog.observedChannel];
isAttackPhaseLog = [divergenceLog.isAttackPhase];

numCh = numel(ServiceChannels);
attackStartSlot = timeSlotDE.ReconnaissanceDuration;
trendWindow = min(100, numel(slots));

%% ==================== Top-1 / Top-2 Hit 여부 계산 (Shadow Q-ranking vs 실제 관측 채널) ====================
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

attackIdx = isAttackPhaseLog;
reconIdx = ~attackIdx;

%% ==================== [그래프 1] Channel Prediction Accuracy over Time (전체 구간, Recon+Attack) ====================
figure;
plot(slots, movmean(top1HitTrend, trendWindow) * 100, ...
     slots, movmean(top2HitTrend, trendWindow) * 100, ...
     'LineWidth', 1.2);
hold on;
yline(randomBaseline_Top1, '--k', sprintf('Random Top-1 (%.0f%%)', randomBaseline_Top1));
yline(randomBaseline_Top2, ':k', sprintf('Random Top-2 (%.0f%%)', randomBaseline_Top2));
xline(attackStartSlot, '--r', 'Attack Start');
hold off;
legend("Top-1 Accuracy (rolling)", "Top-2 Accuracy (rolling)", "Location", "best");
title(sprintf("APJ Shadow DQN: Channel Prediction Accuracy over Time (window=%d)", trendWindow));
xlabel("Time Slot"); ylabel("Accuracy (%)"); ylim([0 100]);
grid on;

fprintf("\n============================================================\n");
fprintf(" Reconnaissance vs Attack Phase Top-1 / Top-2 Prediction Accuracy\n");
fprintf("============================================================\n");
fprintf("Reconnaissance Slots        : %d\n", nnz(reconIdx));
if nnz(reconIdx) > 0
    fprintf("Reconnaissance Top-1 Accuracy : %.2f%%\n", mean(top1HitTrend(reconIdx)) * 100);
    fprintf("Reconnaissance Top-2 Accuracy : %.2f%%\n", mean(top2HitTrend(reconIdx)) * 100);
else
    fprintf("Reconnaissance Top-1/Top-2 Accuracy : N/A (표본 없음)\n");
end
fprintf("------------------------------------------------------------\n");
fprintf("Attack Slots                : %d\n", nnz(attackIdx));
fprintf("Attack Top-1 Accuracy       : %.2f%%\n", mean(top1HitTrend(attackIdx)) * 100);
fprintf("Attack Top-2 Accuracy       : %.2f%%\n", mean(top2HitTrend(attackIdx)) * 100);
fprintf("============================================================\n");

%% ==================== [그래프 2] Target UT ACK Rate / SINR over Time ====================
DebugHelper.printTargetUTSummary();
FigureHelper.plotTargetUTThroughput(100);

%% ==================== [그래프 3] Top-1 vs Top-2 Jamming Hit Rate (Attack 구간, 실제 재밍 자원 기준) ====================
attackAttackIdx = find(attackIdx);   % 논리형 -> 인덱스 벡터

top1HitCount = nnz(top1HitTrend(attackAttackIdx));
top2HitCount = nnz(top2HitTrend(attackAttackIdx));
attackTotalCountBC = numel(attackAttackIdx);

fprintf("\n============================================================\n");
fprintf(" [APJ Shadow DQN] Top-1 vs Top-2 Jamming Hit Rate 요약\n");
fprintf("============================================================\n");
if attackTotalCountBC > 0
    fprintf("① Jamming Hit Rate (Top-1) : %.2f%% (%d / %d)\n", ...
        top1HitCount / attackTotalCountBC * 100, top1HitCount, attackTotalCountBC);
    fprintf("① Jamming Hit Rate (Top-2) : %.2f%% (%d / %d)\n", ...
        top2HitCount / attackTotalCountBC * 100, top2HitCount, attackTotalCountBC);
else
    fprintf("재밍 시도 기록 없음\n");
end
fprintf("============================================================\n");

if attackTotalCountBC > 0
    trendWindowBC = min(100, attackTotalCountBC);
    attackSlotsBC = slots(attackAttackIdx);

    figure;
    plot(attackSlotsBC, movmean(top1HitTrend(attackAttackIdx), trendWindowBC) * 100, 'LineWidth', 1.2, ...
        'Color', [0.85 0.33 0.10]);   % Top-1: 주황
    hold on;
    plot(attackSlotsBC, movmean(top2HitTrend(attackAttackIdx), trendWindowBC) * 100, 'LineWidth', 1.2, ...
        'Color', [0 0.45 0.74]);      % Top-2: 파랑
    yline(randomBaseline_Top1, '--', 'Color', [0.5 0.5 0.5], 'Label', 'Random 기대값 (Top-1, 1/numChannels)');
    yline(randomBaseline_Top2, '--k', 'Random 기대값 (Top-2, 2/numChannels)');
    hold off;

    xlabel("Time Slot"); ylabel("Jamming Hit Rate (%)");
    title(sprintf("APJ Shadow DQN: Top-1 vs Top-2 Jamming Hit Rate (window=%d)", trendWindowBC));
    legend("Top-1", "Top-2", "Location", "best");
    xlim([attackStartSlot numTimeSlots]);
    ylim([0 100]);
    grid on;
end

%% ==================== 검증용 콘솔 출력 (그래프 아님) ====================
% divergenceLog에 실제 주입된 재밍채널(jammingChannels) 기준 hit rate.
% TopKJam=2이므로 위 ①Top-2 값과 반드시 일치해야 함 — 안 맞으면 로직 어긋난 것.
attackHitCount = 0;
attackTotalCount = 0;
for idx = attackAttackIdx
    jc = divergenceLog(idx).jammingChannels;
    if isempty(jc)
        continue;
    end
    attackTotalCount = attackTotalCount + 1;
    if any(divergenceLog(idx).observedChannel == jc)
        attackHitCount = attackHitCount + 1;
    end
end

if attackTotalCount > 0
    fprintf("\n[검증] 실제 주입 재밍채널 기준 Hit Rate (TopKJam=%d) : %.2f%% (%d / %d)\n", ...
        timeSlotDE.TopKJam, attackHitCount / attackTotalCount * 100, attackHitCount, attackTotalCount);
    fprintf("       (위 ①Top-2 값과 일치해야 정상)\n");
end