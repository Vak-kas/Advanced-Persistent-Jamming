clc;
clear;
clear variables;
clear DebugHelper;
close all;

%% ==================== Environment Settings ====================
env;

%% ==================== 채널 생성 ====================
ServiceChannels = Channel.empty(0, numChannels);
ControlChannels = Channel.empty(0, numChannels);
for k = 1:numChannels
    centerFreq_Hz = serviceBandStart_Hz + (k-0.5) * channelSpacing_Hz;
    serviceChannelStart_Hz = centerFreq_Hz - channelBandwidth_Hz/2;
    serviceChannelEnd_Hz   = centerFreq_Hz + channelBandwidth_Hz/2;
    ServiceChannels(k) = Channel(k, ChannelType.Service, serviceChannelStart_Hz, serviceChannelEnd_Hz);
    ControlChannels(k) = Channel(k, ChannelType.Control, 1, 2);
end

%% ==================== Satellite 생성 ====================
satellitePosition = [0 0 satelliteAltitude];
SatelliteNode = Satellite(9999, satellitePosition, numBeams);

%% ==================== Beam 생성 ====================
Beams = BeamFactory.createBeams(numBeams, maxBeamFootprintDiameter, beamRadius, beamSpacing, beamMaxGain_dBi, beam3dBWidth_deg, beamEIRPDensity_dBW_per_MHz, channelBandwidth_Hz);
for beamIndex = 1:numBeams
    SatelliteNode.addBeam(Beams(beamIndex));
end

%% ==================== UT 생성 ====================
UTs = UTFactory.createUTs(Beams, numUTs);

%% ==================== Target Beam 찾기 (헤더 출력/그래프용) ====================
targetBeamIndex = find([Beams.AssociatedUTId] == targetUTId, 1);
if isempty(targetBeamIndex)
    error("mainBC:TargetBeamNotFound", "targetUTId %d 에 연결된 Beam을 찾을 수 없습니다.", targetUTId);
end

%% ==================== APJ 생성 ====================
APJNode = APJ_BCFactory.createAPJ_BC(UTs, Beams, targetUTId, targetJammerDistance);
targetUT = UTs(targetUTId);

fprintf("\n============================================================\n");
fprintf(" Attack: BC-based Predictive Jammer (Top-2)\n");
fprintf("============================================================\n");
fprintf("Target UT         : UT%d\n", targetUT.Id);
fprintf("Target Beam       : Beam%d\n", targetBeamIndex);
fprintf("Num Channels      : %d\n", numChannels);
fprintf("Num Time Slots    : %d\n", numTimeSlots);
fprintf("Reconnaissance Duration : %d\n", reconnaissanceDuration);
fprintf("============================================================\n");

%% ==================== TimeSlot 생성 / 로그 초기화 ====================
timeSlot = TimeSlot();
bcLog = struct('slot', {}, 'observedChannel', {}, 'top1Channel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

%% ==================== Time Slot 루프 ====================
for slotIndex = 1:numTimeSlots
    bcLog = timeSlot.run(slotIndex, UTs, SatelliteNode, APJNode, ServiceChannels, ControlChannels, bcLog);
end

%% ==================== 결과 요약 / 그래프 (기존 진단용) ====================
DebugHelper.printTargetUTSummary();
DebugHelper.plotTargetUTThroughput(100);
DebugHelper.printAPJPredictionSummary(numel(ServiceChannels));   % top-1 예측 정확도(진단용, 콘솔)
DebugHelper.plotAPJAccuracyTrend(100);                            % 기존 내장 그래프(Attack Start 표시 없음, 참고용)

%% ==================== 예측 데이터 한 번만 가져오기 ====================
evalPredData = DebugHelper.APJPredictionStorage('get', []);

%% ==================== [Attack Start 표시 추가] BC Channel Prediction Accuracy over Time ====================
% DebugHelper.plotAPJAccuracyTrend은 Attack Start 표시가 없어서, mainDE와 동일 스타일로 별도 재작성
if ~isempty(evalPredData.slots)
    bcAccSlots = evalPredData.slots;
    bcAccIsHit = double(evalPredData.predicted == evalPredData.actual);   % Top-1 hit 여부
    bcAccTrendWindow = min(100, numel(bcAccSlots));

    figure;
    plot(bcAccSlots, movmean(bcAccIsHit, bcAccTrendWindow) * 100, 'LineWidth', 1.2, ...
        'Color', [0.85 0.33 0.10]);
    hold on;
    yline(100 / numel(ServiceChannels), '--k', sprintf('Random Baseline (%.0f%%)', 100 / numel(ServiceChannels)));
    xline(reconnaissanceDuration, '--r', 'Attack Start');
    hold off;

    xlabel("Time Slot"); ylabel("Accuracy (%)");
    title(sprintf("BC Channel Prediction Accuracy over Time (window=%d)", bcAccTrendWindow));
    ylim([0 100]);
    grid on;
end

%% ==================== [Top-2] Target Beam 선택 채널 시계열 ====================
if ~isempty(bcLog)
    plotSlots = [bcLog.slot];
    plotObserved = [bcLog.observedChannel];
    plotIsAttack = [bcLog.isAttackPhase];

    figure;
    scatter(plotSlots, plotObserved, 5, 'filled');
    hold on;
    for idx = find(plotIsAttack)
        jc = bcLog(idx).jammingChannels;
        if ~isempty(jc)
            plot(repmat(bcLog(idx).slot, 1, numel(jc)), jc, 'r.', 'MarkerSize', 2);
        end
    end
    hold off;
    xlabel("Time Slot"); ylabel("Channel");
    title("Target Beam 선택 채널 (파랑) vs BC Top-2 재밍 채널 (빨강)");
    ylim([0 numChannels + 1]);
    grid on;
end

%% ==================== [Top-1 vs Top-2] Jamming Hit Rate 계산 ====================
if ~isempty(bcLog)
    logIsAttack = [bcLog.isAttackPhase];
    attackIdx = find(logIsAttack);

    top1HitCount = 0;
    top2HitCount = 0;
    attackTotalCount = 0;
    top1HitTrend = false(1, numel(bcLog));
    top2HitTrend = false(1, numel(bcLog));

    for idx = attackIdx
        jc = bcLog(idx).jammingChannels;
        if isempty(jc)
            continue;
        end
        attackTotalCount = attackTotalCount + 1;

        observed = bcLog(idx).observedChannel;

        if ~isempty(bcLog(idx).top1Channel) && observed == bcLog(idx).top1Channel
            top1HitCount = top1HitCount + 1;
            top1HitTrend(idx) = true;
        end

        if any(observed == jc)
            top2HitCount = top2HitCount + 1;
            top2HitTrend(idx) = true;
        end
    end

    fprintf("\n============================================================\n");
    fprintf(" [BC Predictor] Top-1 vs Top-2 평가지표 요약\n");
    fprintf("============================================================\n");
    if attackTotalCount > 0
        fprintf("① Jamming Hit Rate (Top-1) : %.2f%% (%d / %d)\n", ...
            top1HitCount / attackTotalCount * 100, top1HitCount, attackTotalCount);
        fprintf("① Jamming Hit Rate (Top-2) : %.2f%% (%d / %d)\n", ...
            top2HitCount / attackTotalCount * 100, top2HitCount, attackTotalCount);
    else
        fprintf("재밍 시도 기록 없음\n");
    end
else
    fprintf("\n[BC Predictor] 로그 없음\n");
    attackIdx = [];
    top1HitTrend = [];
    top2HitTrend = [];
end

% ---- ② Target Success Rate, ③ Average SINR (기존과 동일) ----
evalUTData = DebugHelper.TargetUTStorage('get', []);
if ~isempty(evalUTData.slots)
    evalUTAttackIdx = logical(evalUTData.isAttackPhase);
    evalUTReconIdx  = ~evalUTAttackIdx;

    fprintf("② Target Success Rate (Recon)    : %.2f%%\n", mean(evalUTData.isACK(evalUTReconIdx)) * 100);
    fprintf("② Target Success Rate (Attack)   : %.2f%%\n", mean(evalUTData.isACK(evalUTAttackIdx)) * 100);
    fprintf("③ Average SINR (Recon)           : %.3f dB\n", mean(evalUTData.SINR_dB(evalUTReconIdx), 'omitnan'));
    fprintf("③ Average SINR (Attack)          : %.3f dB\n", mean(evalUTData.SINR_dB(evalUTAttackIdx), 'omitnan'));
else
    fprintf("Target UT 데이터 없음\n");
end
fprintf("============================================================\n");

%% ---- [통일 포맷] Top-1 vs Top-2 Jamming Hit Rate rolling 그래프 ----
if ~isempty(attackIdx)
    trendWindow = min(100, numel(attackIdx));
    attackSlots = [bcLog(attackIdx).slot];

    figure;
    plot(attackSlots, movmean(top1HitTrend(attackIdx), trendWindow) * 100, 'LineWidth', 1.2, ...
        'Color', [0.85 0.33 0.10]);   % Top-1: 주황
    hold on;
    plot(attackSlots, movmean(top2HitTrend(attackIdx), trendWindow) * 100, 'LineWidth', 1.2, ...
        'Color', [0 0.45 0.74]);      % Top-2: 파랑
    yline(100 * 1 / numChannels, '--', 'Color', [0.5 0.5 0.5], 'Label', 'Random 기대값 (Top-1, 1/numChannels)');
    yline(100 * 2 / numChannels, '--k', 'Random 기대값 (Top-2, 2/numChannels)');
    hold off;

    xlabel("Time Slot"); ylabel("Jamming Hit Rate (%)");
    title(sprintf("BC Predictor: Top-1 vs Top-2 Jamming Hit Rate (window=%d)", trendWindow));
    legend("Top-1", "Top-2", "Location", "best");
    xlim([reconnaissanceDuration numTimeSlots]);
    ylim([0 100]);
    grid on;
end