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
    error("mainD:TargetBeamNotFound", "targetUTId %d 에 연결된 Beam을 찾을 수 없습니다.", targetUTId);
end
targetBeam = Beams(targetBeamIndex);

%% ==================== APJ 생성 ====================
apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);
targetUT = UTs(targetUTId);

fprintf("\n============================================================\n");
fprintf(" RF-Observation + Oracle Shadow DQN Configuration\n");
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
fprintf("============================================================\n");

%% ==================== TimeSlotD 생성 / 로그 초기화 ====================
% TimeSlotD(topKJam): 1 = Top-1 채널만 재밍(기존 동작), 2 = Top-1+Top-2 동시 재밍(기본값)
timeSlotD = TimeSlotD(2);

divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
    'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
    'observedChannel', {}, 'actualACK', {}, 'isAttackPhase', {}, 'jammingChannels', {});

channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

%% ==================== Time Slot 루프 ====================
for slotIndex = 1:numTimeSlots
    [divergenceLog, channelLog] = timeSlotD.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);
end

if isempty(divergenceLog)
    warning("mainD:EmptyDivergenceLog", "divergenceLog가 비어 있습니다."); return;
end
if isempty(channelLog)
    warning("mainD:EmptyChannelLog", "channelLog가 비어 있습니다."); return;
end

%% ==================== 기본 데이터 추출 ====================
slots = [divergenceLog.slot];
lossA = [divergenceLog.lossA];
lossB = [divergenceLog.lossB];
qCosSim = [divergenceLog.qCosSim];
argmaxMatch = [divergenceLog.argmaxMatch];
weightDiffNorm = [divergenceLog.weightDiffNorm];
qA_matrix = vertcat(divergenceLog.qA);
qB_matrix = vertcat(divergenceLog.qB);
actualActions = [divergenceLog.observedChannel];

numCh = numel(ServiceChannels);   % 아래 여러 섹션에서 공통으로 사용

summaryWindow = min(100, numel(slots));
validIdx = numel(slots) - summaryWindow + 1 : numel(slots);
windowSize = summaryWindow;

%% ==================== Target vs Shadow 기본 비교 ====================
figure;
subplot(2,2,1);
plot(slots, lossA, slots, lossB);
legend("Target Beam Agent Loss", "APJ Shadow Agent Loss", "Location", "best");
title("Target / Shadow Loss 비교"); xlabel("Time Slot"); ylabel("Loss");

subplot(2,2,2);
plot(slots, qCosSim);
title("Q-vector Cosine Similarity"); xlabel("Time Slot"); ylabel("Cosine Similarity"); ylim([-1 1.05]);

subplot(2,2,3);
plot(slots, movmean(argmaxMatch, windowSize));
title(sprintf("Argmax Agreement (Moving Avg. %d)", windowSize)); xlabel("Time Slot"); ylabel("Agreement Rate"); ylim([0 1.05]);

subplot(2,2,4);
plot(slots, weightDiffNorm);
title("Weight Difference L2 Norm"); xlabel("Time Slot"); ylabel("Norm");

fprintf("\n============================================================\n");
fprintf(" Target Beam vs APJ Shadow DQN Summary\n");
fprintf("============================================================\n");
fprintf("최근 %d슬롯 평균 Argmax Agreement : %.2f%%\n", summaryWindow, mean(argmaxMatch(validIdx), "omitnan") * 100);
fprintf("최근 %d슬롯 평균 Q Cosine Similarity : %.6f\n", summaryWindow, mean(qCosSim(validIdx), "omitnan"));
fprintf("최종 Weight Diff Norm : %.6f\n", weightDiffNorm(end));
fprintf("============================================================\n");

%% ==================== 최근 100슬롯 Policy Top-K ====================
% Top-1 Agreement: Target Top-1 == Shadow Top-1
% Rank-2 Rescue: Shadow Top-1은 틀렸지만 Target Top-1 == Shadow Top-2
% Cumulative Top-2 Hit: Target Top-1이 Shadow Top-2 후보 안에 포함

recentTop1Count = 0; recentRank2RescueCount = 0; recentTop2HitCount = 0;
for idx = validIdx
    [~, targetRanking] = sort(qA_matrix(idx, :), 'descend');
    [~, shadowRanking] = sort(qB_matrix(idx, :), 'descend');
    targetTop1 = targetRanking(1); shadowTop1 = shadowRanking(1); shadowTop2 = shadowRanking(2);

    if targetTop1 == shadowTop1
        recentTop1Count = recentTop1Count + 1;
    elseif targetTop1 == shadowTop2
        recentRank2RescueCount = recentRank2RescueCount + 1;
    end
    if any(targetTop1 == shadowRanking(1:2))
        recentTop2HitCount = recentTop2HitCount + 1;
    end
end

recentTop1Rate = recentTop1Count / summaryWindow;
recentRank2RescueRate = recentRank2RescueCount / summaryWindow;
recentTop2Rate = recentTop2HitCount / summaryWindow;

fprintf("\n============================================================\n");
fprintf(" Target Beam vs APJ Shadow Top-K Policy Summary\n");
fprintf("============================================================\n");
fprintf("최근 %d슬롯 Top-1 Agreement       : %.2f%%\n", summaryWindow, recentTop1Rate * 100);
fprintf("최근 %d슬롯 Rank-2 Rescue         : %.2f%%\n", summaryWindow, recentRank2RescueRate * 100);
fprintf("최근 %d슬롯 Cumulative Top-2 Hit : %.2f%%\n", summaryWindow, recentTop2Rate * 100);
fprintf("============================================================\n");

%% ==================== 최근 100슬롯 Actual Action Top-K ====================
recentActualTop1Count = 0; recentActualRank2RescueCount = 0; recentActualTop2HitCount = 0;
for idx = validIdx
    [~, shadowRanking] = sort(qB_matrix(idx, :), 'descend');
    targetActualAction = actualActions(idx);
    shadowTop1 = shadowRanking(1); shadowTop2 = shadowRanking(2);

    if targetActualAction == shadowTop1
        recentActualTop1Count = recentActualTop1Count + 1;
    elseif targetActualAction == shadowTop2
        recentActualRank2RescueCount = recentActualRank2RescueCount + 1;
    end
    if any(targetActualAction == shadowRanking(1:2))
        recentActualTop2HitCount = recentActualTop2HitCount + 1;
    end
end

recentActualTop1Rate = recentActualTop1Count / summaryWindow;
recentActualRank2RescueRate = recentActualRank2RescueCount / summaryWindow;
recentActualTop2Rate = recentActualTop2HitCount / summaryWindow;

fprintf("\n============================================================\n");
fprintf(" APJ Actual Channel Prediction Top-K Summary\n");
fprintf("============================================================\n");
fprintf("최근 %d슬롯 Actual Top-1 Hit              : %.2f%%\n", summaryWindow, recentActualTop1Rate * 100);
fprintf("최근 %d슬롯 Actual Rank-2 Rescue          : %.2f%%\n", summaryWindow, recentActualRank2RescueRate * 100);
fprintf("최근 %d슬롯 Actual Cumulative Top-2 Hit : %.2f%%\n", summaryWindow, recentActualTop2Rate * 100);
fprintf("============================================================\n");

%% ==================== 전체 구간 Top-K ====================
totalCount = numel(slots);
totalTop1Count = 0; totalRank2RescueCount = 0; totalTop2HitCount = 0;
totalActualTop1Count = 0; totalActualRank2RescueCount = 0; totalActualTop2HitCount = 0;

for idx = 1:totalCount
    [~, targetRanking] = sort(qA_matrix(idx, :), 'descend');
    [~, shadowRanking] = sort(qB_matrix(idx, :), 'descend');
    targetTop1 = targetRanking(1); shadowTop1 = shadowRanking(1); shadowTop2 = shadowRanking(2);

    if targetTop1 == shadowTop1
        totalTop1Count = totalTop1Count + 1;
    elseif targetTop1 == shadowTop2
        totalRank2RescueCount = totalRank2RescueCount + 1;
    end
    if any(targetTop1 == shadowRanking(1:2))
        totalTop2HitCount = totalTop2HitCount + 1;
    end

    targetActualAction = actualActions(idx);
    if targetActualAction == shadowTop1
        totalActualTop1Count = totalActualTop1Count + 1;
    elseif targetActualAction == shadowTop2
        totalActualRank2RescueCount = totalActualRank2RescueCount + 1;
    end
    if any(targetActualAction == shadowRanking(1:2))
        totalActualTop2HitCount = totalActualTop2HitCount + 1;
    end
end

totalTop1Rate = totalTop1Count / totalCount;
totalRank2RescueRate = totalRank2RescueCount / totalCount;
totalTop2Rate = totalTop2HitCount / totalCount;
totalActualTop1Rate = totalActualTop1Count / totalCount;
totalActualRank2RescueRate = totalActualRank2RescueCount / totalCount;
totalActualTop2Rate = totalActualTop2HitCount / totalCount;

fprintf("\n============================================================\n");
fprintf(" Overall Top-K Summary\n");
fprintf("============================================================\n");
fprintf("전체 %d슬롯 Policy Top-1 Agreement       : %.2f%%\n", totalCount, totalTop1Rate * 100);
fprintf("전체 %d슬롯 Policy Rank-2 Rescue         : %.2f%%\n", totalCount, totalRank2RescueRate * 100);
fprintf("전체 %d슬롯 Policy Cumulative Top-2 Hit : %.2f%%\n\n", totalCount, totalTop2Rate * 100);
fprintf("전체 %d슬롯 Actual Top-1 Hit              : %.2f%%\n", totalCount, totalActualTop1Rate * 100);
fprintf("전체 %d슬롯 Actual Rank-2 Rescue          : %.2f%%\n", totalCount, totalActualRank2RescueRate * 100);
fprintf("전체 %d슬롯 Actual Cumulative Top-2 Hit : %.2f%%\n", totalCount, totalActualTop2Rate * 100);
fprintf("============================================================\n");

%% ==================== Target Beam 채널 선택 Collapse 진단 ====================
chSlots = [channelLog.slot];
chSelected = [channelLog.channel];
chEpsilon = [channelLog.epsilon];
windowSize2 = min(100, numel(chSlots));
modeShare = zeros(size(chSlots));

for i = 1:numel(chSlots)
    startIdx = max(1, i - windowSize2 + 1);
    counts = histcounts(chSelected(startIdx:i), 0.5 : 1 : (numCh + 0.5));
    modeShare(i) = max(counts) / numel(chSelected(startIdx:i));
end

figure;
subplot(3,1,1);
scatter(chSlots, chSelected, 5, 'filled');
title("Target Beam 선택 채널"); xlabel("Time Slot"); ylabel("Channel"); ylim([0 numCh + 1]);

subplot(3,1,2);
plot(chSlots, chEpsilon);
title("Target Beam Epsilon"); xlabel("Time Slot"); ylabel("Epsilon");

subplot(3,1,3);
plot(chSlots, modeShare);
title(sprintf("이동창(%d) 내 최빈 채널 점유율", windowSize2)); xlabel("Time Slot"); ylabel("Mode Share"); ylim([0 1.05]);

fprintf("\n============================================================\n");
fprintf(" Target Beam Channel Collapse Summary\n");
fprintf("============================================================\n");
[finalCounts, ~] = histcounts(chSelected, 0.5 : 1 : (numCh + 0.5));
[maxCount, maxCh] = max(finalCounts);
fprintf("전체 %d슬롯 중 CH%d 선택 : %d회 (%.2f%%)\n", numel(chSlots), maxCh, maxCount, maxCount / numel(chSlots) * 100);
fprintf("마지막 Epsilon : %.6f\n", chEpsilon(end));

if numel(modeShare) >= windowSize2
    collapseSearchIdx = windowSize2 : numel(modeShare);
    localCollapseIdx = find(modeShare(collapseSearchIdx) >= 0.9, 1);
    if ~isempty(localCollapseIdx)
        fprintf("최빈 채널 점유율 90%% 최초 도달 슬롯 : %d\n", chSlots(collapseSearchIdx(localCollapseIdx)));
    else
        fprintf("최빈 채널 점유율이 90%%를 넘은 적 없음\n");
    end
else
    fprintf("Collapse 판단을 위한 충분한 슬롯 수 없음\n");
end
fprintf("============================================================\n");

%% ==================== [신규] Attack Start 기준 Top-1 / Top-2 예측 정확도 추이 ====================
% qB_matrix(Shadow Q-value 로그)와 actualActions(Target 실제 채널 로그)로
% 슬롯마다 "Shadow가 예측한 Top-1/Top-2 후보 안에 Target 실제 채널이
% 있었는가"를 계산 -> rolling window로 시계열 그래프화.
% (TimeSlotD.m의 실제 재밍 로직과는 별개의 순수 진단/분석용 지표)

attackStartSlot = timeSlotD.ReconnaissanceDuration;

top1HitTrend = false(size(slots));
top2HitTrend = false(size(slots));

for idx = 1:numel(slots)
    [~, shadowRanking] = sort(qB_matrix(idx, :), 'descend');
    actualCh = actualActions(idx);

    top1HitTrend(idx) = (actualCh == shadowRanking(1));
    top2HitTrend(idx) = any(actualCh == shadowRanking(1:min(2, numel(shadowRanking))));
end

trendWindow = min(100, numel(slots));
randomBaseline_Top1 = 100 / numCh;
randomBaseline_Top2 = 100 * min(2, numCh) / numCh;

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
title(sprintf("APJ Shadow DQN Actual Channel Prediction Accuracy (window=%d)", trendWindow));
xlabel("Time Slot"); ylabel("Accuracy (%)"); ylim([0 100]);

attackIdx = slots > attackStartSlot;
reconIdx = ~attackIdx;

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

%% ==================== [신규] 공격 실제 적중률 (Top-K Jamming) ====================
% TimeSlotD.m이 실제로 재밍한 채널 집합(jammingChannels, Top-1 또는 Top-1+Top-2)과
% Target 실제 채널이 겹쳤는지를 attack phase에서만 집계.
% (위 top1/top2HitTrend는 "Shadow 예측" 진단이고, 이건 "실제 재밍 성공률".)

attackHitCount = 0;
attackTotalCount = 0;

for idx = find(attackIdx)
    jc = divergenceLog(idx).jammingChannels;
    if isempty(jc)
        continue;
    end
    attackTotalCount = attackTotalCount + 1;
    if any(divergenceLog(idx).observedChannel == jc)
        attackHitCount = attackHitCount + 1;
    end
end

fprintf("\n============================================================\n");
fprintf(" Actual Jamming Hit Rate (TopKJam = %d)\n", timeSlotD.TopKJam);
fprintf("============================================================\n");
if attackTotalCount > 0
    fprintf("재밍 시도 슬롯 수  : %d\n", attackTotalCount);
    fprintf("재밍 적중 슬롯 수  : %d\n", attackHitCount);
    fprintf("재밍 적중률        : %.2f%%\n", attackHitCount / attackTotalCount * 100);
else
    fprintf("재밍 시도 기록 없음 (divergenceLog에 jammingChannels 필드가 없거나 비어있음)\n");
end
fprintf("============================================================\n");

%% ==================== [신규] Target UT ACK/SINR: Attack Start 이후 전용 요약 ====================
% DebugHelper.recordTargetUTOutcome이 TimeSlotD.run() 안에서 이미
% obj.ReconnaissanceDuration을 넘겨 기록하고 있으므로, BC 파이프라인과
% 동일한 함수로 Reconnaissance/Attack phase 요약을 그대로 재사용 가능.
DebugHelper.printTargetUTSummary();
FigureHelper.plotTargetUTThroughput(100);

%% ==================== Target / Shadow Q-value 절대 차이 ====================
qAbsDiff = abs(qA_matrix - qB_matrix);

figure;
subplot(2,1,1);
plot(slots, mean(qAbsDiff, 2));
title("Target / Shadow Q-value 평균 절대 차이"); xlabel("Time Slot"); ylabel("mean(|Q_Target-Q_Shadow|)");

subplot(2,1,2);
[~, finalGreedyChannel] = max(qA_matrix(end, :));
plot(slots, qA_matrix(:, finalGreedyChannel), slots, qB_matrix(:, finalGreedyChannel));
legend(sprintf("Target CH%d", finalGreedyChannel), sprintf("Shadow CH%d", finalGreedyChannel), "Location", "best");
title(sprintf("최종 Greedy Channel CH%d Q-value", finalGreedyChannel)); xlabel("Time Slot"); ylabel("Q-value");

fprintf("\n============================================================\n");
fprintf(" Final Channel-wise Q Difference\n");
fprintf("============================================================\n");
for channelIndex = 1:numCh
    fprintf("CH %2d : Target=%+.8f | Shadow=%+.8f | Diff=%.8f\n", channelIndex, qA_matrix(end, channelIndex), qB_matrix(end, channelIndex), qAbsDiff(end, channelIndex));
end
fprintf("전체 채널 평균 절대 차이 : %.8f\n", mean(qAbsDiff(end, :)));
fprintf("============================================================\n");

%% ==================== 발산 크기 종합 ====================
weightNormA = [divergenceLog.weightNormA];
weightNormB = [divergenceLog.weightNormB];
relativeWeightDiff = weightDiffNorm ./ ((weightNormA + weightNormB) / 2 + eps);
qL2Dist = [divergenceLog.qL2Dist];
lossDiff = abs(lossA - lossB);

figure;
subplot(2,2,1);
plot(slots, qL2Dist);
title("Q-vector L2 Distance"); xlabel("Time Slot"); ylabel("L2 Distance");

subplot(2,2,2);
plot(slots, lossDiff);
title("|Loss_{Target}-Loss_{Shadow}|"); xlabel("Time Slot"); ylabel("Loss Difference");

subplot(2,2,3);
plot(slots, weightDiffNorm, slots, weightNormA, slots, weightNormB);
legend("||W_T-W_S||", "||W_T||", "||W_S||", "Location", "best");
title("Weight Norm 비교"); xlabel("Time Slot"); ylabel("Norm");

subplot(2,2,4);
plot(slots, relativeWeightDiff * 100);
title("상대적 Weight Difference"); xlabel("Time Slot"); ylabel("Relative Difference (%)");

%% ==================== 채널별 Q-value 절대 차이 히트맵 ====================
figure;
imagesc(slots, 1:numCh, qAbsDiff');
set(gca, 'YDir', 'normal'); colorbar;
xlabel("Time Slot"); ylabel("Channel"); title("Channel-wise |Q_{Target}-Q_{Shadow}|");

%% ==================== 최종 발산 요약 ====================
fprintf("\n============================================================\n");
fprintf(" Final Divergence Summary\n");
fprintf("============================================================\n");
fprintf("최종 Q-vector L2 거리 : %.8f\n", qL2Dist(end));
fprintf("최종 ||W_Target||      : %.8f\n", weightNormA(end));
fprintf("최종 ||W_Shadow||      : %.8f\n", weightNormB(end));
fprintf("최종 ||W_Target-W_Shadow|| : %.8f\n", weightDiffNorm(end));
fprintf("최종 상대적 Weight 차이 : %.4f%%\n", relativeWeightDiff(end) * 100);

validLossDiff = lossDiff(validIdx);
if any(~isnan(validLossDiff))
    fprintf("최근 %d슬롯 평균 |Loss_Target-Loss_Shadow| : %.8f\n", summaryWindow, mean(validLossDiff, "omitnan"));
else
    fprintf("최근 %d슬롯 Loss 데이터 없음 또는 학습 전\n", summaryWindow);
end
fprintf("============================================================\n");