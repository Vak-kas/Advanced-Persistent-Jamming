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
    error("mainB:TargetBeamNotFound", "targetUTId %d 에 연결된 Beam을 찾을 수 없습니다.", targetUTId);
end
targetBeam = Beams(targetBeamIndex);

%% ==================== APJ 생성 (독립 학습 GA-Dueling DQN) ====================
apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);

% ---- Agent를 "독립 학습"(epsilon-greedy 자기 행동 선택) 버전으로 교체 ----
apjd.Agent = APJAgentDueling(apjd);

targetUT = UTs(targetUTId);

fprintf("\n============================================================\n");
fprintf(" Benchmark: GA-Dueling DQN, 독립 학습 (원 논문 충실 재현)\n");
fprintf(" Action=자기 선택(epsilon-greedy) / Reward=자기 공격 성공 여부(SINR 추정)\n");
fprintf("============================================================\n");
fprintf("Target UT         : UT%d\n", targetUT.Id);
fprintf("Target Beam       : Beam%d\n", targetBeamIndex);
fprintf("Target-APJ 거리  : %.3f km\n", targetUT.distanceTo(apjd) / 1e3);
fprintf("Num Channels      : %d\n", numChannels);
fprintf("Num Time Slots    : %d\n", numTimeSlots);
fprintf("Reconnaissance Duration : %d (이 구간엔 재머가 행동하지 않음)\n", reconnaissanceDuration);
fprintf("Jammer Epsilon    : start=%.3f, min=%.3f, decay=%.3f\n", ...
    apjd.Agent.Epsilon, apjd.Agent.EpsilonMin, apjd.Agent.EpsilonDecay);
fprintf("============================================================\n");

%% ==================== TimeSlotB 생성 / 로그 초기화 ====================
timeSlotB = TimeSlotB();

gLog = struct('slot', {}, 'isAttackPhase', {}, 'observedChannel', {}, ...
    'jammingChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'attackerSuccess', {});

channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

%% ==================== Time Slot 루프 ====================
for slotIndex = 1:numTimeSlots
    [gLog, channelLog] = timeSlotB.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, gLog, channelLog);
end

if isempty(gLog)
    warning("mainB:EmptyLog", "gLog가 비어 있습니다."); return;
end

%% ==================== 기본 데이터 추출 ====================
slots = [gLog.slot];
isAttackPhaseLog = [gLog.isAttackPhase];
attackIdx = find(isAttackPhaseLog);

observedChannel = [gLog.observedChannel];
jammingChannel = [gLog.jammingChannel];
attackerSuccess = [gLog.attackerSuccess];

%% ==================== ① Jamming Hit Rate ====================
attackHitCount = 0;
attackTotalCount = numel(attackIdx);
for idx = attackIdx
    if ~isempty(gLog(idx).jammingChannel) && gLog(idx).jammingChannel == gLog(idx).observedChannel
        attackHitCount = attackHitCount + 1;
    end
end

fprintf("\n============================================================\n");
fprintf(" ① Jamming Hit Rate (Independent GA-Dueling DQN)\n");
fprintf("============================================================\n");
if attackTotalCount > 0
    fprintf("공격 슬롯 수      : %d\n", attackTotalCount);
    fprintf("재밍 적중 슬롯 수 : %d\n", attackHitCount);
    fprintf("Jamming Hit Rate  : %.2f%%\n", attackHitCount / attackTotalCount * 100);
else
    fprintf("공격 슬롯 없음\n");
end
fprintf("============================================================\n");

%% ==================== ④ Cumulative Reward (Attacker) ====================
% apjRewardFunction(attackerSuccess) = attackerSuccess*apjSuccessReward + (~attackerSuccess)*apjFailureReward
attackerRewardPerSlot = double(attackerSuccess(attackIdx)) * apjSuccessReward + ...
    double(~attackerSuccess(attackIdx)) * apjFailureReward;
cumulativeAttackerReward = cumsum(attackerRewardPerSlot);

figure;
plot(slots(attackIdx), cumulativeAttackerReward, 'LineWidth', 1.2);
xlabel("Time Slot"); ylabel("Cumulative Reward (Attacker)");
title("Independent GA-Dueling DQN: Cumulative Attacker Reward");
grid on;

fprintf("\n============================================================\n");
fprintf(" ④ Cumulative Reward (Attacker 관점, 자기 공격 성공 기준)\n");
fprintf("============================================================\n");
fprintf("최종 Cumulative Reward : %.2f\n", cumulativeAttackerReward(end));
fprintf("공격 성공률(attackerSuccess mean) : %.2f%%\n", mean(attackerSuccess(attackIdx)) * 100);
fprintf("============================================================\n");

%% ==================== Jamming Hit Rate / Attacker Success 추이 ====================
trendWindow = min(100, numel(attackIdx));
hitTrend = double(jammingChannel(attackIdx) == observedChannel(attackIdx));

figure;
plot(slots(attackIdx), movmean(hitTrend, trendWindow) * 100, 'LineWidth', 1.2);
hold on;
plot(slots(attackIdx), movmean(attackerSuccess(attackIdx), trendWindow) * 100, 'LineWidth', 1.2);
yline(100 / numChannels, '--k', sprintf('Random (%.0f%%)', 100 / numChannels));
hold off;
legend("Jamming Hit Rate (rolling)", "Attacker Success Rate (rolling, SINR 기준)", "Location", "best");
xlabel("Time Slot"); ylabel("Rate (%)");
title(sprintf("Independent GA-Dueling DQN Learning Curve (window=%d)", trendWindow));
ylim([0 100]);
grid on;

%% ==================== Target UT ACK/SINR 요약 ====================
DebugHelper.printTargetUTSummary();
FigureHelper.plotTargetUTThroughput(100);
FigureHelper.plotTargetUTSuccessRate(100);