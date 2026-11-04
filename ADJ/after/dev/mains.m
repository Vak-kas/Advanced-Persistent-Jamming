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
    error("mainS:TargetBeamNotFound", "targetUTId %d 에 연결된 Beam을 찾을 수 없습니다.", targetUTId);
end

%% ==================== APJ 생성 (Sweep Jammer는 예측을 안 쓰므로, Id/TargetUTId만 필요) ====================
apj = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);
targetUT = UTs(targetUTId);

%% ==================== TimeSlotS 생성 / 로그 초기화 ====================
dwellSlots = 1;   % 채널 쌍 하나당 재밍을 유지하는 슬롯 수 (1 = 매 슬롯 다음 쌍으로 이동)
timeSlotS = TimeSlotS(numChannels, dwellSlots);

fprintf("\n============================================================\n");
fprintf(" Baseline: Sweep(Comb) Jammer\n");
fprintf("============================================================\n");
fprintf("Target UT         : UT%d\n", targetUT.Id);
fprintf("Target Beam       : Beam%d\n", targetBeamIndex);
fprintf("Num Channels      : %d\n", numChannels);
fprintf("Num Time Slots    : %d\n", numTimeSlots);
fprintf("Reconnaissance Duration : %d\n", reconnaissanceDuration);
fprintf("Dwell Slots (채널 쌍당 유지 슬롯) : %d\n", dwellSlots);
fprintf("Channel Pairs 순서 : ");
for p = 1:size(timeSlotS.ChannelPairs, 1)
    fprintf("(%d,%d) ", timeSlotS.ChannelPairs(p,1), timeSlotS.ChannelPairs(p,2));
end
fprintf("\n============================================================\n");

sweepLog = struct('slot', {}, 'observedChannel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

%% ==================== Time Slot 루프 ====================
for slotIndex = 1:numTimeSlots
    sweepLog = timeSlotS.run(slotIndex, UTs, SatelliteNode, apj, ServiceChannels, ControlChannels, targetBeamIndex, sweepLog);
end

if isempty(sweepLog)
    warning("mainS:EmptySweepLog", "sweepLog가 비어 있습니다."); return;
end

%% ==================== 기본 데이터 추출 ====================
slots = [sweepLog.slot];
observedChannels = [sweepLog.observedChannel];
isAttackPhaseLog = [sweepLog.isAttackPhase];
attackIdx = find(isAttackPhaseLog);

% Sweep 재밍 채널 개수(=채널쌍 크기)로 랜덤 기대값 계산
sweepJamSize = 2;
if ~isempty(attackIdx)
    sweepJamSize = numel(sweepLog(attackIdx(1)).jammingChannels);
end
randomBaseline = 100 * min(sweepJamSize, numChannels) / numChannels;

%% ==================== [그래프 1] Target UT ACK Rate / SINR over Time ====================
DebugHelper.printTargetUTSummary();
FigureHelper.plotTargetUTThroughput(100);
FigureHelper.plotTargetUTSuccessRate(100);

%% ==================== Jamming Hit 여부 계산 (전체 슬롯) ====================
hitTrend = false(size(slots));
for i = 1:numel(slots)
    jc = sweepLog(i).jammingChannels;
    if ~isempty(jc)
        hitTrend(i) = any(observedChannels(i) == jc);
    end
end

attackHitCount = nnz(hitTrend(attackIdx));
attackTotalCount = numel(attackIdx);

fprintf("\n============================================================\n");
fprintf(" [Sweep Jammer] 평가지표 요약\n");
fprintf("============================================================\n");
if attackTotalCount > 0
    fprintf("① Jamming Hit Rate (Attack 구간) : %.2f%% (%d / %d)  (이론적 무작위 기대값: %.2f%%)\n", ...
        attackHitCount / attackTotalCount * 100, attackHitCount, attackTotalCount, randomBaseline);
else
    fprintf("재밍 시도 기록 없음\n");
end

evalUTData = DebugHelper.TargetUTStorage('get', []);
if ~isempty(evalUTData.slots)
    evalUTAttackIdx = logical(evalUTData.isAttackPhase);
    evalUTReconIdx = ~evalUTAttackIdx;

    fprintf("② Target Success Rate (Recon)    : %.2f%%\n", mean(evalUTData.isACK(evalUTReconIdx)) * 100);
    fprintf("② Target Success Rate (Attack)   : %.2f%%\n", mean(evalUTData.isACK(evalUTAttackIdx)) * 100);
    fprintf("③ Average SINR (Recon)           : %.3f dB\n", mean(evalUTData.SINR_dB(evalUTReconIdx), 'omitnan'));
    fprintf("③ Average SINR (Attack)          : %.3f dB\n", mean(evalUTData.SINR_dB(evalUTAttackIdx), 'omitnan'));
else
    fprintf("Target UT 데이터 없음\n");
end
fprintf("============================================================\n");

%% ==================== [그래프 2] Jamming Hit Rate over Time (rolling, Attack 구간) ====================
if attackTotalCount > 0
    trendWindow = min(100, attackTotalCount);
    attackSlots = slots(attackIdx);

    figure;
    plot(attackSlots, movmean(hitTrend(attackIdx), trendWindow) * 100, 'LineWidth', 1.2, ...
        'Color', [0 0.45 0.74]);
    hold on;
    yline(randomBaseline, '--k', sprintf('Random 기대값 (%d/numChannels, %.1f%%)', sweepJamSize, randomBaseline));
    hold off;

    xlabel("Time Slot"); ylabel("Jamming Hit Rate (%)");
    title(sprintf("Sweep Jammer: Jamming Hit Rate over Time (window=%d)", trendWindow));
    xlim([reconnaissanceDuration numTimeSlots]);
    ylim([0 100]);
    grid on;
end

%% ==================== [그래프 3] Target Beam 선택 채널 vs Sweep 재밍 채널 시계열 ====================
figure;
scatter(slots, observedChannels, 5, 'filled');
hold on;
for idx = attackIdx
    jc = sweepLog(idx).jammingChannels;
    if ~isempty(jc)
        plot(repmat(sweepLog(idx).slot, 1, numel(jc)), jc, 'r.', 'MarkerSize', 2);
    end
end
if ~isempty(attackIdx)
    xline(slots(attackIdx(1)), '--r', 'Attack Start', 'LineWidth', 1.2);
end
hold off;
xlabel("Time Slot"); ylabel("Channel");
title("Target Beam 선택 채널 (파랑) vs Sweep 재밍 채널 (빨강)");
ylim([0 numChannels + 1]);
grid on;