clc;
clear;
clear variables;
close all;



%% ================================================================
% Environment Settings
% ================================================================

env;



%% ================================================================
% Node 생성
% ================================================================

% ---------------- UT 생성 ----------------

UTs = ...
    UT.empty(0, numUTs);


for n = 1:numUTs

    x = rand() * groundWidth;
    y = rand() * groundHeight;
    z = 0;

    utPosition = ...
        [x, y, z];

    isTarget = ...
        (n == targetUTId);


    UTs(n) = UT( ...
        n, ...
        utPosition, ...
        utTxPower_dBm, ...
        isTarget, ...
        K, ...
        phi);
end



% ---------------- Satellite 생성 ----------------

Satellites = ...
    Satellite.empty(0, numSatellites);


for n = 1:numSatellites

    pos = ...
        UTs(n).getPosition();


    x = pos(1);
    y = pos(2);
    z = satelliteAltitude;


    satellitePosition = ...
        [x, y, z];


    associatedUTId = ...
        UTs(n).Id;


    Satellites(n) = Satellite( ...
        n, ...
        satellitePosition, ...
        satelliteTxPower_dBm, ...
        associatedUTId, ...
        sinrThreshold_dB, ...
        satelliteRxGain_dBi, ...
        satelliteGOverT_dB);
end



% ---------------- APJ 생성 ----------------

targetPosition = ...
    UTs(targetUTId).getPosition();


theta = ...
    2 * pi * rand();


x = ...
    targetPosition(1) + ...
    targetJammerDistance * cos(theta);

y = ...
    targetPosition(2) + ...
    targetJammerDistance * sin(theta);

z = 0;


apjPosition = ...
    [x, y, z];


APJ = APJ( ...
    1001, ...
    apjPosition, ...
    apjTxPower_dBm, ...
    targetUTId, ...
    APJsinrThreshold_db, ...
    K, ...
    phi);



% ---------------- 위치 Plot ----------------

ax = ...
    FigureHelper.plotUTDeployment( ...
        UTs, ...
        groundWidth, ...
        groundHeight);


FigureHelper.plotAPJ( ...
    ax, ...
    APJ);



%% ================================================================
% Channel 생성
% ================================================================

ServiceChannels = ...
    Channel.empty(0, K);

ControlChannels = ...
    Channel.empty(0, K);


for k = 1:K

    centerFreq_Hz = ...
        serviceBandStart_Hz + ...
        (k - 0.5) * channelSpacing_Hz;


    serviceChannelStart_Hz = ...
        centerFreq_Hz - ...
        channelBandwidth_Hz / 2;


    serviceChannelEnd_Hz = ...
        centerFreq_Hz + ...
        channelBandwidth_Hz / 2;


    ServiceChannels(k) = Channel( ...
        k, ...
        ChannelType.Service, ...
        serviceChannelStart_Hz, ...
        serviceChannelEnd_Hz);


    ControlChannels(k) = Channel( ...
        k, ...
        ChannelType.Control, ...
        1, ...
        2);
end



%% ================================================================
% History 초기화
% ================================================================

actualChannels = ...
    nan(1, numTimeSlots);

utGreedyChannels = ...
    nan(1, numTimeSlots);

apjPredictedChannels = ...
    nan(1, numTimeSlots);


actualPredictionCorrect = ...
    nan(1, numTimeSlots);

greedyAgreementCorrect = ...
    nan(1, numTimeSlots);


qMarginHistory = ...
    nan(1, numTimeSlots);


qCorrelationHistory = ...
    nan(1, numTimeSlots);


spearmanCorrelationHistory = ...
    nan(1, numTimeSlots);


utGreedyRankInAPJHistory = ...
    nan(1, numTimeSlots);


% 행 = Time Slot
% 열 = Top-k
topKHitHistory = ...
    nan(numTimeSlots, K);



timeSlot = ...
    TimeSlot();


targetACKHistory = ...
    zeros(1, numTimeSlots);



%% ================================================================
% HARQ Confusion Matrix
% ================================================================

TP = 0;
FN = 0;
FP = 0;
TN = 0;



%% ================================================================
% Simulation
% ================================================================

for slotIndex = 1:numTimeSlots

    [result, actualTargetACK, shadowResult] = ...
        timeSlot.run( ...
            slotIndex, ...
            UTs, ...
            Satellites, ...
            APJ, ...
            ServiceChannels, ...
            ControlChannels);



    %% ------------------------------------------------------------
    % APJ HARQ 예측 결과 누적
    % -------------------------------------------------------------

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



    %% ------------------------------------------------------------
    % Shadowing 결과 저장
    % -------------------------------------------------------------

    if ~isempty(shadowResult.ActualChannel)

        actualChannels(slotIndex) = ...
            shadowResult.ActualChannel;


        utGreedyChannels(slotIndex) = ...
            shadowResult.UTGreedyChannel;


        apjPredictedChannels(slotIndex) = ...
            shadowResult.APJPredictedChannel;


        actualPredictionCorrect(slotIndex) = ...
            double( ...
                shadowResult.ActualPredictionCorrect);


        greedyAgreementCorrect(slotIndex) = ...
            double( ...
                shadowResult.GreedyAgreementCorrect);


        qMarginHistory(slotIndex) = ...
            shadowResult.QMargin;


        qCorrelationHistory(slotIndex) = ...
            shadowResult.QCorrelation;


        spearmanCorrelationHistory(slotIndex) = ...
            shadowResult.SpearmanCorrelation;


        utGreedyRankInAPJHistory(slotIndex) = ...
            shadowResult.UTGreedyRankInAPJ;


        topKHitHistory(slotIndex, :) = ...
            shadowResult.TopKHit;

    end



    %% ------------------------------------------------------------
    % Target UT ACK/NACK
    % -------------------------------------------------------------

    targetACKHistory(slotIndex) = ...
        actualTargetACK;

end



%% ================================================================
% APJ HARQ Prediction
% ================================================================

DebugHelper.printHARQPredictionResult( ...
    TP, FN, FP, TN);



%% ================================================================
% 마지막 Transition 완성
% ================================================================

if timeSlot.UseAgent

    for utIndex = 1:numel(UTs)

        finalObservation = ...
            UTs(utIndex).ObservationManager.observe( ...
                ServiceChannels, ...
                UTs);


        UTs(utIndex).Agent.setCurrentState( ...
            finalObservation);


        UTs(utIndex).Agent.completeTransition();


        UTs(utIndex).Agent.train();

    end
end



% ---------------- APJ ----------------

finalAPJObservation = ...
    APJ.ObservationManager.observe( ...
        ServiceChannels, ...
        UTs);


APJ.Agent.setCurrentState( ...
    finalAPJObservation);


APJ.Agent.completeTransition();


APJ.Agent.train();



%% ================================================================
% APJ Shadowing Analysis
% ================================================================

validSlots = ...
    ~isnan(actualPredictionCorrect);


actualCorrect = ...
    actualPredictionCorrect(validSlots);


greedyCorrect = ...
    greedyAgreementCorrect(validSlots);



%% ------------------------------------------------------------
% Cumulative Accuracy
% -------------------------------------------------------------

cumulativeActualAccuracy = ...
    cumsum(actualCorrect) ./ ...
    (1:numel(actualCorrect));


cumulativeGreedyAccuracy = ...
    cumsum(greedyCorrect) ./ ...
    (1:numel(greedyCorrect));



%% ------------------------------------------------------------
% Moving Accuracy
% -------------------------------------------------------------

windowSize = 100;


movingActualAccuracy = ...
    movmean( ...
        actualCorrect, ...
        [windowSize - 1, 0]);


movingGreedyAccuracy = ...
    movmean( ...
        greedyCorrect, ...
        [windowSize - 1, 0]);



%% ------------------------------------------------------------
% Final Accuracy
% -------------------------------------------------------------

finalActualAccuracy = ...
    mean(actualCorrect);


finalGreedyAccuracy = ...
    mean(greedyCorrect);


fprintf("\n");
fprintf("------------------------------------------------------------\n");
fprintf("APJ Shadowing Performance\n");
fprintf("------------------------------------------------------------\n");

fprintf( ...
    "  Actual Action Prediction Accuracy : %.2f %%\n", ...
    finalActualAccuracy * 100);

fprintf( ...
    "  Greedy Policy Agreement           : %.2f %%\n", ...
    finalGreedyAccuracy * 100);

fprintf("------------------------------------------------------------\n");



%% ================================================================
% Q-Margin Analysis
% ================================================================

validMarginSlots = ...
    ~isnan(qMarginHistory) & ...
    ~isnan(greedyAgreementCorrect);


validMargins = ...
    qMarginHistory(validMarginSlots);


validGreedyAgreement = ...
    greedyAgreementCorrect(validMarginSlots);



% ---------------- Correct / Wrong ----------------

correctMargins = ...
    validMargins( ...
        validGreedyAgreement == 1);


wrongMargins = ...
    validMargins( ...
        validGreedyAgreement == 0);


fprintf("\n");
fprintf("------------------------------------------------------------\n");
fprintf("Q-Margin Analysis\n");
fprintf("------------------------------------------------------------\n");

fprintf( ...
    "  Correct Mean Q-Margin : %.4f\n", ...
    mean(correctMargins));

fprintf( ...
    "  Wrong Mean Q-Margin   : %.4f\n", ...
    mean(wrongMargins));

fprintf("------------------------------------------------------------\n");



%% ------------------------------------------------------------
% Q-Margin vs Greedy Agreement
% -------------------------------------------------------------

marginEdges = ...
    [0 0.05 0.1 0.2 0.5 1 Inf];


numBins = ...
    numel(marginEdges) - 1;


marginAccuracy = ...
    nan(1, numBins);


marginCount = ...
    zeros(1, numBins);



for binIndex = 1:numBins

    indices = ...
        validMargins >= marginEdges(binIndex) & ...
        validMargins < marginEdges(binIndex + 1);


    marginCount(binIndex) = ...
        sum(indices);


    if marginCount(binIndex) > 0

        marginAccuracy(binIndex) = ...
            mean( ...
                validGreedyAgreement(indices));

    end
end



fprintf("\n");
fprintf("------------------------------------------------------------\n");
fprintf("Q-Margin vs Greedy Agreement\n");
fprintf("------------------------------------------------------------\n");


for binIndex = 1:numBins

    if isinf( ...
            marginEdges(binIndex + 1))

        fprintf( ...
            "  [%5.2f, Inf ) : %6.2f %%  (N=%d)\n", ...
            marginEdges(binIndex), ...
            marginAccuracy(binIndex) * 100, ...
            marginCount(binIndex));

    else

        fprintf( ...
            "  [%5.2f, %5.2f) : %6.2f %%  (N=%d)\n", ...
            marginEdges(binIndex), ...
            marginEdges(binIndex + 1), ...
            marginAccuracy(binIndex) * 100, ...
            marginCount(binIndex));

    end
end


fprintf("------------------------------------------------------------\n");



%% ================================================================
% Pearson Q-Vector Correlation
% ================================================================

validCorrelationSlots = ...
    ~isnan(qCorrelationHistory);


validCorrelations = ...
    qCorrelationHistory( ...
        validCorrelationSlots);


meanCorrelation = ...
    mean(validCorrelations);


medianCorrelation = ...
    median(validCorrelations);



numValidCorrelations = ...
    numel(validCorrelations);


lastStartIndex = ...
    max( ...
        1, ...
        numValidCorrelations - 199);


last200MeanCorrelation = ...
    mean( ...
        validCorrelations( ...
            lastStartIndex:end));



fprintf("\n");
fprintf("------------------------------------------------------------\n");
fprintf("Q-Vector Correlation Analysis\n");
fprintf("------------------------------------------------------------\n");

fprintf( ...
    "  Mean Pearson Correlation     : %.4f\n", ...
    meanCorrelation);

fprintf( ...
    "  Median Pearson Correlation   : %.4f\n", ...
    medianCorrelation);

fprintf( ...
    "  Last 200 Mean Correlation    : %.4f\n", ...
    last200MeanCorrelation);

fprintf("------------------------------------------------------------\n");



%% ------------------------------------------------------------
% Correct / Wrong Correlation
% -------------------------------------------------------------

validCompareSlots = ...
    ~isnan(qCorrelationHistory) & ...
    ~isnan(greedyAgreementCorrect);


correctCorrelation = ...
    qCorrelationHistory( ...
        validCompareSlots & ...
        greedyAgreementCorrect == 1);


wrongCorrelation = ...
    qCorrelationHistory( ...
        validCompareSlots & ...
        greedyAgreementCorrect == 0);


fprintf( ...
    "  Correct Mean Correlation     : %.4f\n", ...
    mean(correctCorrelation));

fprintf( ...
    "  Wrong Mean Correlation       : %.4f\n", ...
    mean(wrongCorrelation));

fprintf("------------------------------------------------------------\n");



%% ================================================================
% Spearman Rank Correlation
% ================================================================

validSpearmanSlots = ...
    ~isnan(spearmanCorrelationHistory);


validSpearman = ...
    spearmanCorrelationHistory( ...
        validSpearmanSlots);


meanSpearman = ...
    mean(validSpearman);


medianSpearman = ...
    median(validSpearman);


numValidSpearman = ...
    numel(validSpearman);


lastSpearmanStartIndex = ...
    max( ...
        1, ...
        numValidSpearman - 199);


last200MeanSpearman = ...
    mean( ...
        validSpearman( ...
            lastSpearmanStartIndex:end));


fprintf("\n");
fprintf("------------------------------------------------------------\n");
fprintf("Q-Vector Rank Correlation Analysis\n");
fprintf("------------------------------------------------------------\n");

fprintf( ...
    "  Mean Spearman Correlation    : %.4f\n", ...
    meanSpearman);

fprintf( ...
    "  Median Spearman Correlation  : %.4f\n", ...
    medianSpearman);

fprintf( ...
    "  Last 200 Mean Spearman       : %.4f\n", ...
    last200MeanSpearman);

fprintf("------------------------------------------------------------\n");



%% ================================================================
% Top-K Hit Rate
% ================================================================

validRankSlots = ...
    ~isnan(utGreedyRankInAPJHistory);


topKHitRate = ...
    mean( ...
        topKHitHistory(validRankSlots, :), ...
        1, ...
        'omitnan') * 100;


fprintf("\n");
fprintf("------------------------------------------------------------\n");
fprintf("Top-K Hit Rate\n");
fprintf("------------------------------------------------------------\n");


for k = 1:K

    fprintf( ...
        "  Top-%2d Hit Rate : %6.2f %%\n", ...
        k, ...
        topKHitRate(k));

end


fprintf("------------------------------------------------------------\n");



%% ================================================================
% UT Greedy Action의 APJ Rank Distribution
% ================================================================

validRanks = ...
    utGreedyRankInAPJHistory( ...
        validRankSlots);


rankCounts = ...
    histcounts( ...
        validRanks, ...
        0.5:1:(K + 0.5));


rankPercentage = ...
    rankCounts / ...
    sum(rankCounts) * 100;


fprintf("\n");
fprintf("------------------------------------------------------------\n");
fprintf("UT Greedy Action Rank in APJ\n");
fprintf("------------------------------------------------------------\n");


for rankIndex = 1:K

    fprintf( ...
        "  Rank %2d : %6.2f %%  (N=%d)\n", ...
        rankIndex, ...
        rankPercentage(rankIndex), ...
        rankCounts(rankIndex));

end


fprintf("------------------------------------------------------------\n");



%% ================================================================
% Graph 1 : Pearson / Spearman over Time
% ================================================================

correlationSlots = ...
    find(validCorrelationSlots);


spearmanSlots = ...
    find(validSpearmanSlots);


windowSizeCorrelation = 100;


movingCorrelation = ...
    movmean( ...
        validCorrelations, ...
        [windowSizeCorrelation - 1, 0]);


movingSpearman = ...
    movmean( ...
        validSpearman, ...
        [windowSizeCorrelation - 1, 0]);


figure;


plot( ...
    correlationSlots, ...
    movingCorrelation, ...
    'LineWidth', 2);


hold on;


plot( ...
    spearmanSlots, ...
    movingSpearman, ...
    'LineWidth', 2);


xlabel('Time Slot');

ylabel('Correlation');

title( ...
    'UT-APJ Q-Vector Similarity');


legend( ...
    'Pearson Correlation', ...
    'Spearman Rank Correlation', ...
    'Location', ...
    'best');


ylim([-1 1]);

grid on;



%% ================================================================
% Graph 2 : Top-K Hit Rate
% ================================================================

figure;


bar( ...
    1:K, ...
    topKHitRate);


xlabel( ...
    'Top-K');


ylabel( ...
    'Hit Rate (%)');


title( ...
    'APJ Top-K Prediction Hit Rate');


xticks( ...
    1:K);


ylim( ...
    [0 100]);


grid on;



%% ================================================================
% Graph 3 : UT Greedy Action Rank in APJ
% ================================================================

figure;


bar( ...
    1:K, ...
    rankPercentage);


xlabel( ...
    'APJ Rank of UT Greedy Action');


ylabel( ...
    'Percentage of Slots (%)');


title( ...
    'Rank Distribution of Target UT Greedy Action in APJ');


xticks( ...
    1:K);


ylim( ...
    [0 100]);


grid on;