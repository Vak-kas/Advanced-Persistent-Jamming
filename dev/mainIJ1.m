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
    error("mainIJ1:TargetBeamNotFound", "targetUTId %d 에 연결된 Beam을 찾을 수 없습니다.", targetUTId);
end

%% ==================== Intelligent Jammer 생성 ====================
ij = IntelligentJammerFactory.createIntelligentJammer(UTs, Beams, targetUTId, targetJammerDistance);
targetUT = UTs(targetUTId);

fprintf("\n============================================================\n");
fprintf(" DQN-IJ1 (No Reconnaissance — IJ 완전 비활성 후 공격과 동시에 학습 시작)\n");
fprintf(" (TimeSlotIJ, DryRun=false)\n");
fprintf("============================================================\n");
fprintf("Target UT          : UT%d\n", targetUT.Id);
fprintf("Target Beam        : Beam%d\n", targetBeamIndex);
fprintf("IJ 위치            : (%.3f, %.3f) km\n", ij.Position(1) / 1e3, ij.Position(2) / 1e3);
fprintf("Target-IJ 거리     : %.3f km\n", targetUT.distanceTo(ij) / 1e3);
fprintf("Num Beams          : %d\n", numel(Beams));
fprintf("Num Channels       : %d\n", numChannels);
fprintf("Num Time Slots     : %d\n", numTimeSlots);
fprintf("Reconnaissance     : 1 ~ %d (IJ 완전 비활성)\n", reconnaissanceDuration);
fprintf("Attack Phase       : %d ~ %d (IJ 온라인 학습+공격 동시 시작)\n", reconnaissanceDuration + 1, numTimeSlots);
fprintf("Jamming Budget     : %d channels/slot\n", size(ij.Agent.ActionTable, 2));
fprintf("Action Space Size  : %d (C(%d,%d))\n", ij.Agent.NumActions, numChannels, size(ij.Agent.ActionTable, 2));
fprintf("============================================================\n");

%% ==================== TimeSlotIJ 생성 (DryRun=false) / 로그 초기화 ====================
timeSlotIJ = TimeSlotIJ(reconnaissanceDuration);
timeSlotIJ.DryRun = false;

ijLog = struct('slot', {}, 'isAttackPhase', {}, 'dryRunActive', {}, 'lossIJ', {}, ...
    'jammedChannels', {}, 'selectedChannels', {}, 'nextJamChannels', {}, ...
    'targetChannel', {}, 'targetHit', {}, 'targetACK', {}, 'targetSINR_dB', {}, ...
    'rewardIJ', {}, 'epsilonIJ', {}, 'selectionMethod', {}, 'qValuesIJ', {});

channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

%% ==================== Time Slot 루프 ====================
for slotIndex = 1:numTimeSlots
    [ijLog, channelLog] = timeSlotIJ.run(slotIndex, UTs, SatelliteNode, ij, ServiceChannels, ControlChannels, targetBeamIndex, ijLog, channelLog);
end

if isempty(ijLog)
    warning("mainIJ1:EmptyIJLog", "ijLog가 비어 있습니다."); return;
end
if isempty(channelLog)
    warning("mainIJ1:EmptyChannelLog", "channelLog가 비어 있습니다."); return;
end

%% ==================== 기본 데이터 추출 ====================
slots = [ijLog.slot];
targetHitTrend = [ijLog.targetHit];
rewardTrend = [ijLog.rewardIJ];
isAttackPhaseLog = [ijLog.isAttackPhase];

trendWindow = min(100, numel(slots));
randomBaseline_HitRate = 100 * size(ij.Agent.ActionTable, 2) / numChannels;

attackIdx = find(isAttackPhaseLog);
attackSlots = slots(attackIdx);
attackHitTrend = targetHitTrend(attackIdx);
attackRewardTrend = rewardTrend(attackIdx);
attackTrendWindow = min(100, numel(attackSlots));

%% ==================== [그래프 1] Jamming Hit Rate over Time (Attack Phase만) ====================
if isempty(attackSlots)
    warning("mainIJ1:NoAttackSlots", "Attack Phase 슬롯이 없습니다 (numTimeSlots <= reconnaissanceDuration).");
else
    figure;
    plot(attackSlots, movmean(attackHitTrend, attackTrendWindow) * 100, 'LineWidth', 1.2);
    hold on;
    yline(randomBaseline_HitRate, '--k', sprintf('Random Hit Rate (%.0f%%)', randomBaseline_HitRate));
    xline(reconnaissanceDuration, '--r', 'Attack Start');
    hold off;
    title(sprintf("DQN-IJ1 (No-Recon-Training): Jamming Hit Rate over Time (Attack Phase, window=%d)", attackTrendWindow));
    xlabel("Time Slot"); ylabel("Hit Rate (%)"); ylim([0 100]);
    grid on;

    fprintf("\n============================================================\n");
    fprintf(" DQN-IJ1 Jamming Hit Rate 요약 (Attack Phase 전용, slot > %d)\n", reconnaissanceDuration);
    fprintf("============================================================\n");
    fprintf("Attack Slots               : %d\n", numel(attackIdx));
    fprintf("Attack 전체 Hit Rate        : %.2f%% (%d / %d)\n", ...
        mean(attackHitTrend) * 100, nnz(attackHitTrend), numel(attackHitTrend));
    fprintf("Attack 최근 %d슬롯 Hit Rate   : %.2f%%\n", ...
        attackTrendWindow, mean(attackHitTrend(end-attackTrendWindow+1:end)) * 100);
    fprintf("Random 기대값               : %.2f%%\n", randomBaseline_HitRate);
    fprintf("============================================================\n");
end

%% ==================== [그래프 2] Target UT ACK Rate / SINR over Time ====================
DebugHelper.printTargetUTSummary();
FigureHelper.plotTargetUTThroughput(100);

%% ==================== [그래프 3] IJ Reward over Time (Attack Phase만) ====================
if ~isempty(attackSlots)
    figure;
    plot(attackSlots, movmean(attackRewardTrend, attackTrendWindow), 'LineWidth', 1.2);
    xline(reconnaissanceDuration, '--r', 'Attack Start');
    title(sprintf("DQN-IJ1: Reward over Time (Attack Phase, window=%d)", attackTrendWindow));
    xlabel("Time Slot"); ylabel("Reward (Eq.24, self-sensed)");
    grid on;

    fprintf("\n[검증] 평균 Reward(Attack Phase 최근 %d슬롯): %.4f\n", ...
        attackTrendWindow, mean(attackRewardTrend(end-attackTrendWindow+1:end)));
end

%% ==================== 결과 저장 (IJ2와 비교용) ====================
save('mainIJ1_results.mat', 'ijLog', 'channelLog', 'reconnaissanceDuration', 'numTimeSlots');
fprintf("\n[저장 완료] mainIJ1_results.mat\n");