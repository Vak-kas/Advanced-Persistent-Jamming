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
    error("mainC:TargetBeamNotFound", "targetUTId %d 에 연결된 Beam을 찾을 수 없습니다.", targetUTId);
end

%% ==================== APJ 생성 (Fixed Comb Jammer는 예측을 안 쓰므로, Id/TargetUTId만 필요) ====================
apj = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);
targetUT = UTs(targetUTId);

%% ==================== TimeSlotC 생성 / 로그 초기화 ====================
% fixedChannels: 처음부터 끝까지 고정으로 재밍할 채널 목록
fixedChannels = [3 5];
timeSlotC = TimeSlotC(fixedChannels);

fprintf("\n============================================================\n");
fprintf(" Baseline: Fixed-Channel Comb Jammer\n");
fprintf("============================================================\n");
fprintf("Target UT         : UT%d\n", targetUT.Id);
fprintf("Target Beam       : Beam%d\n", targetBeamIndex);
fprintf("Num Channels      : %d\n", numChannels);
fprintf("Num Time Slots    : %d\n", numTimeSlots);
fprintf("Reconnaissance Duration : %d\n", reconnaissanceDuration);
fprintf("Fixed Jamming Channels  : %s\n", mat2str(fixedChannels));
fprintf("============================================================\n");

combLog = struct('slot', {}, 'observedChannel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

%% ==================== Time Slot 루프 ====================
for slotIndex = 1:numTimeSlots
    combLog = timeSlotC.run(slotIndex, UTs, SatelliteNode, apj, ServiceChannels, ControlChannels, targetBeamIndex, combLog);
end

if isempty(combLog)
    warning("mainC:EmptyCombLog", "combLog가 비어 있습니다."); return;
end

%% ==================== Jamming Hit Rate 계산 ====================
slots = [combLog.slot];
isAttackPhaseLog = [combLog.isAttackPhase];
attackIdx = find(isAttackPhaseLog);

attackHitCount = 0;
attackTotalCount = 0;

for idx = attackIdx
    jc = combLog(idx).jammingChannels;
    if isempty(jc)
        continue;
    end
    attackTotalCount = attackTotalCount + 1;
    if any(combLog(idx).observedChannel == jc)
        attackHitCount = attackHitCount + 1;
    end
end

fprintf("\n============================================================\n");
fprintf(" Fixed Comb Jammer Actual Jamming Hit Rate\n");
fprintf("============================================================\n");
if attackTotalCount > 0
    fprintf("재밍 시도 슬롯 수  : %d\n", attackTotalCount);
    fprintf("재밍 적중 슬롯 수  : %d\n", attackHitCount);
    fprintf("재밍 적중률        : %.2f%%\n", attackHitCount / attackTotalCount * 100);
else
    fprintf("재밍 시도 기록 없음\n");
end
fprintf("============================================================\n");

%% ==================== Target UT ACK/SINR 요약 ====================
DebugHelper.printTargetUTSummary();
FigureHelper.plotTargetUTThroughput(100);
FigureHelper.plotTargetUTSuccessRate(100);

%% ==================== Target Beam 선택 채널 시계열 (참고용) ====================
figure;
scatter(slots, [combLog.observedChannel], 5, 'filled');
hold on;
if ~isempty(attackIdx)
    xline(slots(attackIdx(1)), '--r', 'Attack Start', 'LineWidth', 1.2);
    yline(fixedChannels, ':r');
end
hold off;
xlabel("Time Slot"); ylabel("Channel");
title(sprintf("Target Beam 선택 채널 vs 고정 재밍 채널 %s", mat2str(fixedChannels)));
ylim([0 numChannels + 1]);
grid on;


%% ==================== [추가] 평가지표 요약 (①②③) ====================
% ① Jamming Hit Rate, ② Target Success Rate, ③ Average SINR
% ④ Cumulative Reward는 이 baseline(Fixed Comb, 학습/reward 없음)에는
% 해당 없음 — 학습 기반 방법(APJ/BC/FC-DQN)에서만 집계.

evalSlots = [combLog.slot];
evalIsAttack = [combLog.isAttackPhase];
evalAttackIdx = find(evalIsAttack);
evalReconIdx = find(~evalIsAttack);

evalObserved = [combLog.observedChannel];

% ---- ① Jamming Hit Rate (슬롯별 hit 여부, rolling 그래프용) ----
evalHitTrend = false(size(evalSlots));
for i = 1:numel(evalSlots)
    jc = combLog(i).jammingChannels;
    if ~isempty(jc)
        evalHitTrend(i) = any(evalObserved(i) == jc);
    end
end

evalAttackHitCount = sum(evalHitTrend(evalAttackIdx));
evalAttackTotalCount = numel(evalAttackIdx);

fprintf("\n============================================================\n");
fprintf(" [Comb Jammer] 평가지표 요약\n");
fprintf("============================================================\n");
fprintf("① Jamming Hit Rate (Attack 구간) : %.2f%% (%d / %d)\n", ...
    evalAttackHitCount / max(evalAttackTotalCount,1) * 100, evalAttackHitCount, evalAttackTotalCount);

% ---- ② Target Success Rate, ③ Average SINR : DebugHelper.TargetUTStorage 재사용 ----
evalUTData = DebugHelper.TargetUTStorage('get', []);
if ~isempty(evalUTData.slots)
    evalUTAttackIdx = evalUTData.isAttackPhase;
    evalUTReconIdx = ~evalUTAttackIdx;

    fprintf("② Target Success Rate (Recon)    : %.2f%%\n", mean(evalUTData.isACK(evalUTReconIdx)) * 100);
    fprintf("② Target Success Rate (Attack)   : %.2f%%\n", mean(evalUTData.isACK(evalUTAttackIdx)) * 100);
    fprintf("③ Average SINR (Recon)           : %.3f dB\n", mean(evalUTData.SINR_dB(evalUTReconIdx), 'omitnan'));
    fprintf("③ Average SINR (Attack)          : %.3f dB\n", mean(evalUTData.SINR_dB(evalUTAttackIdx), 'omitnan'));
else
    fprintf("Target UT 데이터 없음\n");
end
fprintf("============================================================\n");

%% ---- ① Jamming Hit Rate rolling 그래프 ----
if evalAttackTotalCount > 0
    evalTrendWindow = min(100, evalAttackTotalCount);
    figure;
    plot(evalSlots(evalAttackIdx), movmean(evalHitTrend(evalAttackIdx), evalTrendWindow) * 100, 'LineWidth', 1.2);
    hold on;
    yline(100 * min(numel(combLog(evalAttackIdx(1)).jammingChannels), numChannels) / numChannels, ...
        '--k', 'Fixed Channel(s) 고정 비율');
    hold off;
    xlabel("Time Slot"); ylabel("Jamming Hit Rate (%)");
    title(sprintf("Comb Jammer: Jamming Hit Rate over Time (window=%d)", evalTrendWindow));
    ylim([0 100]);
    grid on;
end