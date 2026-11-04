clc;
clear;
clear variables;
close all;



%% ==================== Environment Settings ====================
env;



%% ==================== Node 생성 ====================
% UT 생성
UTs = UT.empty(0, numUTs);
for n = 1:numUTs
    x = rand() * groundWidth;
    y = rand() * groundHeight;
    z = 0;

    utPosition = [x, y, z];

    isTarget = (n== targetUTId);

    UTs(n) = UT(n, utPosition, utTxPower_dBm, isTarget, K, phi);
end

% Satellite 생성
Satellites = Satellite.empty(0, numSatellites);
for n = 1:numSatellites

    utPos = UTs(n).getPosition();
    utX = utPos(1);
    utY = utPos(2);


    satXMin = utX - satelliteCoverageRadius;
    satXMax = utX + satelliteCoverageRadius;

    satYMin = utY - satelliteCoverageRadius;
    satYMax = utY + satelliteCoverageRadius;

    % Generate a valid satellite ground projection

    while true
        x = satXMin + (satXMax - satXMin) * rand();
        y = satYMin + (satYMax - satYMin) * rand();
        groundDistance = sqrt((x - utX)^2 + (y - utY)^2);

        if groundDistance <= satelliteCoverageRadius
            break;
        end

    end
    satellitePosition = [x, y, z];
    associatedUTId = UTs(n).Id;

    Satellites(n) = Satellite(n, satellitePosition, satelliteTxPower_dBm, associatedUTId, sinrThreshold_dB, satelliteRxGain_dBi, satelliteGOverT_dB);
end
DebugHelper.printSatelliteInfo(Satellites(1));


% APJ 생성
targetPosition = UTs(targetUTId).getPosition();

theta = 2 * pi * rand(); %랜덤 방향 설정

x = targetPosition(1) + targetJammerDistance * cos(theta);
y = targetPosition(2) + targetJammerDistance * sin(theta);
z = 0;

apjPosition = [x, y, z];
APJ = APJ(1001, apjPosition, apjTxPower_dBm, targetUTId, APJsinrThreshold_db, K, phi);


% 좌표 표시
ax = FigureHelper.plotUTDeployment(UTs, groundWidth, groundHeight);
FigureHelper.plotAPJ(ax, APJ);



DebugHelper.printAssociationDistances(UTs, Satellites);



%% ==================== 채널 생성 ====================
ServiceChannels = Channel.empty(0, K);
ControlChannels = Channel.empty(0, K);

for k = 1:K
    centerFreq_Hz = serviceBandStart_Hz + (k-0.5) * channelSpacing_Hz;

    serviceChannelStart_Hz = centerFreq_Hz - channelBandwidth_Hz/2;
    serviceChannelEnd_Hz   = centerFreq_Hz + channelBandwidth_Hz/2;
    
    ServiceChannels(k) = Channel(k, ChannelType.Service, serviceChannelStart_Hz, serviceChannelEnd_Hz);
    ControlChannels(k) = Channel(k, ChannelType.Control, 1, 2);
end

% DebugHelper.printChannels(ServiceChannels, ControlChannels);


%% ==================== Time Slot 마다 수행 ====================

actualChannels = nan(1, numTimeSlots);
utGreedyChannels = nan(1, numTimeSlots);
apjPredictedChannels = nan(1, numTimeSlots);
actualPredictionCorrect = nan(1, numTimeSlots);
greedyAgreementCorrect = nan(1, numTimeSlots);
qMarginHistory = nan(1, numTimeSlots);
qCorrelationHistory = nan(1, numTimeSlots);

timeSlot = TimeSlot();
targetACKHistory = zeros(1, numTimeSlots);

TP = 0;
FN = 0;
FP = 0;
TN = 0;

for slotIndex = 1:numTimeSlots

    [result, actualTargetACK, shadowResult] = timeSlot.run(slotIndex, UTs, Satellites, APJ, ServiceChannels, ControlChannels);

    % APJ HARQ 예측 결과 누적
    switch result
        case 0
            TP = TP + 1;

        case 1
            FN = FN + 1;

        case 2
            FP = FP + 1;

        case 3
            TN = TN + 1;

        otherwise
            error( ...
                "Main:UnknownResult", ...
                "알 수 없는 result 값입니다: %d", ...
                result);
    end

    % Shadowing 결과 저장

    if ~isempty(shadowResult.ActualChannel)

        actualChannels(slotIndex) = shadowResult.ActualChannel;

        utGreedyChannels(slotIndex) = shadowResult.UTGreedyChannel;

        apjPredictedChannels(slotIndex) = shadowResult.APJPredictedChannel;

        actualPredictionCorrect(slotIndex) = double(shadowResult.ActualPredictionCorrect);

        greedyAgreementCorrect(slotIndex) = double(shadowResult.GreedyAgreementCorrect);

        qMarginHistory(slotIndex) = shadowResult.QMargin;

        qCorrelationHistory(slotIndex) = shadowResult.QCorrelation;
        

        

    end

    % Target UT의 실제 ACK/NACK 결과 저장
    targetACKHistory(slotIndex) = actualTargetACK;
end



%% APJ HARQ 예측 결과 출력
DebugHelper.printHARQPredictionResult(TP, FN, FP, TN);


%% 마지막 Transition 완성
if timeSlot.UseAgent
    for utIndex = 1:numel(UTs)

        finalObservation = ...
            UTs(utIndex).ObservationManager.observe( ...
                ServiceChannels, UTs);

        UTs(utIndex).Agent.setCurrentState(finalObservation);
        UTs(utIndex).Agent.completeTransition();

        % 마지막 Transition을 포함하여 한 번 더 학습
        UTs(utIndex).Agent.train();
    end
end

finalAPJObservation = APJ.ObservationManager.observe(ServiceChannels, UTs);
APJ.Agent.setCurrentState(finalAPJObservation);
APJ.Agent.completeTransition();

% 마지막 Transition을 포함하여 한 번 더 학습
APJ.Agent.train();


%% ==================== APJ Shadowing Analysis ====================
% 
% validSlots = ~isnan(actualPredictionCorrect);
% 
% actualCorrect = actualPredictionCorrect(validSlots);
% 
% greedyCorrect = greedyAgreementCorrect(validSlots);
% 
% %% 1. Cumulative Accuracy
% 
% 
% 
% 
% cumulativeActualAccuracy = cumsum(actualCorrect) ./ (1:numel(actualCorrect));
% 
% cumulativeGreedyAccuracy = cumsum(greedyCorrect) ./ (1:numel(greedyCorrect));
% 
% %% 2. Moving Accuracy
% 
% windowSize = 100;
% 
% movingActualAccuracy = movmean(actualCorrect, [windowSize-1 0]);
% 
% movingGreedyAccuracy = movmean(greedyCorrect, [windowSize-1 0]);
% 
% %% 3. 전체 / 최근 200 Slot Accuracy
% 
% % 전체 평균
% 
% finalActualAccuracy = mean(actualCorrect);
% 
% finalGreedyAccuracy = mean(greedyCorrect);
% 
% % 최근 200개의 유효 Shadowing 결과
% 
% numValidShadowSlots = numel(actualCorrect);
% 
% last200StartIndex = max(1, numValidShadowSlots - 199);
% 
% last200ActualCorrect = actualCorrect(last200StartIndex:end);
% 
% last200GreedyCorrect = greedyCorrect(last200StartIndex:end);
% 
% % 최근 200 Slot 평균
% 
% last200ActualAccuracy = mean(last200ActualCorrect);
% 
% last200GreedyAccuracy = mean(last200GreedyCorrect);
% 
% %% 결과 출력
% 
% fprintf("\n");
% 
% fprintf("------------------------------------------------------------\n");
% 
% fprintf("APJ Shadowing Performance\n");
% 
% fprintf("------------------------------------------------------------\n");
% 
% fprintf("  Overall Actual Action Prediction : %.2f %%\n", finalActualAccuracy * 100);
% 
% fprintf("  Overall Greedy Policy Agreement  : %.2f %%\n", finalGreedyAccuracy * 100);
% 
% fprintf("------------------------------------------------------------\n");
% 
% fprintf("  Last 200 Actual Prediction       : %.2f %%\n", last200ActualAccuracy * 100);
% 
% fprintf("  Last 200 Greedy Agreement        : %.2f %%\n", last200GreedyAccuracy * 100);
% 
% fprintf("------------------------------------------------------------\n");
% 
% %% ==================== Q-Margin Analysis ====================
% 
% validMarginSlots = ...
%     ~isnan(qMarginHistory) & ...
%     ~isnan(greedyAgreementCorrect);
% 
% validMargins = qMarginHistory(validMarginSlots);
% validGreedyAgreement = greedyAgreementCorrect(validMarginSlots);
% 
% 
% %% 1. Correct / Wrong의 평균 Q-Margin 비교
% 
% correctMargins = ...
%     validMargins(validGreedyAgreement == 1);
% 
% wrongMargins = ...
%     validMargins(validGreedyAgreement == 0);
% 
% 
% fprintf("\n");
% fprintf("------------------------------------------------------------\n");
% fprintf("Q-Margin Analysis\n");
% fprintf("------------------------------------------------------------\n");
% 
% fprintf( ...
%     "  Correct Mean Q-Margin : %.4f\n", ...
%     mean(correctMargins));
% 
% fprintf( ...
%     "  Wrong Mean Q-Margin   : %.4f\n", ...
%     mean(wrongMargins));
% 
% fprintf("------------------------------------------------------------\n");
% 
% 
% %% 2. Q-Margin 구간별 Greedy Agreement
% 
% marginEdges = [0 0.05 0.1 0.2 0.5 1 Inf];
% 
% numBins = numel(marginEdges) - 1;
% 
% marginAccuracy = nan(1, numBins);
% marginCount = zeros(1, numBins);
% 
% 
% for binIndex = 1:numBins
% 
%     indices = ...
%         validMargins >= marginEdges(binIndex) & ...
%         validMargins < marginEdges(binIndex + 1);
% 
%     marginCount(binIndex) = sum(indices);
% 
%     if marginCount(binIndex) > 0
%         marginAccuracy(binIndex) = ...
%             mean(validGreedyAgreement(indices));
%     end
% end
% 
% 
% fprintf("\n");
% fprintf("------------------------------------------------------------\n");
% fprintf("Q-Margin vs Greedy Agreement\n");
% fprintf("------------------------------------------------------------\n");
% 
% for binIndex = 1:numBins
% 
%     if isinf(marginEdges(binIndex + 1))
% 
%         fprintf( ...
%             "  [%5.2f, Inf ) : %6.2f %%  (N=%d)\n", ...
%             marginEdges(binIndex), ...
%             marginAccuracy(binIndex) * 100, ...
%             marginCount(binIndex));
% 
%     else
% 
%         fprintf( ...
%             "  [%5.2f, %5.2f) : %6.2f %%  (N=%d)\n", ...
%             marginEdges(binIndex), ...
%             marginEdges(binIndex + 1), ...
%             marginAccuracy(binIndex) * 100, ...
%             marginCount(binIndex));
% 
%     end
% end
% 
% fprintf("------------------------------------------------------------\n");
% 
% 
% %% ==================== Q-Vector Correlation Analysis ====================
% 
% validCorrelationSlots = ~isnan(qCorrelationHistory);
% 
% validCorrelations = ...
%     qCorrelationHistory(validCorrelationSlots);
% 
% meanCorrelation = mean(validCorrelations);
% medianCorrelation = median(validCorrelations);
% 
% 
% % 마지막 200개 correlation
% numValidCorrelations = numel(validCorrelations);
% 
% lastStartIndex = ...
%     max(1, numValidCorrelations - 199);
% 
% last200MeanCorrelation = ...
%     mean(validCorrelations(lastStartIndex:end));
% 
% 
% fprintf("\n");
% fprintf("------------------------------------------------------------\n");
% fprintf("Q-Vector Correlation Analysis\n");
% fprintf("------------------------------------------------------------\n");
% 
% fprintf( ...
%     "  Mean Pearson Correlation     : %.4f\n", ...
%     meanCorrelation);
% 
% fprintf( ...
%     "  Median Pearson Correlation   : %.4f\n", ...
%     medianCorrelation);
% 
% fprintf( ...
%     "  Last 200 Mean Correlation    : %.4f\n", ...
%     last200MeanCorrelation);
% 
% fprintf("------------------------------------------------------------\n");
% 
% 
% %% Correct / Wrong Correlation 비교
% 
% validCompareSlots = ...
%     ~isnan(qCorrelationHistory) & ...
%     ~isnan(greedyAgreementCorrect);
% 
% 
% correctCorrelation = ...
%     qCorrelationHistory( ...
%         validCompareSlots & greedyAgreementCorrect == 1);
% 
% wrongCorrelation = ...
%     qCorrelationHistory( ...
%         validCompareSlots & greedyAgreementCorrect == 0);
% 
% 
% fprintf( ...
%     "  Correct Mean Correlation     : %.4f\n", ...
%     mean(correctCorrelation));
% 
% fprintf( ...
%     "  Wrong Mean Correlation       : %.4f\n", ...
%     mean(wrongCorrelation));
% 
% fprintf("------------------------------------------------------------\n");
% 
% %% ==================== Q-Vector Correlation Graph ====================
% 
% correlationSlots = find(validCorrelationSlots);
% 
% windowSizeCorrelation = 100;
% 
% movingCorrelation = ...
%     movmean(validCorrelations, ...
%         [windowSizeCorrelation - 1, 0]);
% 
% 
% figure;
% 
% plot( ...
%     correlationSlots, ...
%     validCorrelations, ...
%     'LineWidth', 0.5);
% 
% hold on;
% 
% plot( ...
%     correlationSlots, ...
%     movingCorrelation, ...
%     'LineWidth', 2);
% 
% xlabel('Time Slot');
% ylabel('Pearson Correlation');
% 
% title('UT-APJ Q-Vector Correlation');
% 
% legend( ...
%     'Slot-wise Correlation', ...
%     sprintf('%d-slot Moving Average', windowSizeCorrelation), ...
%     'Location', 'best');
% 
% ylim([-1 1]);
% grid on;