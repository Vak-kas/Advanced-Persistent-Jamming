clc;
clear;
close all;

env;

fprintf("============================================================\n");
fprintf("APJ SINR Threshold Calibration\n");
fprintf("============================================================\n\n");


%% ==================== 1. Satellite 생성 ====================

satellitePosition = [0 0 satelliteAltitude];

SatelliteNode = Satellite( ...
    9999, ...
    satellitePosition, ...
    numBeams ...
);


%% ==================== 2. Beam 생성 ====================

Beams = BeamFactory.createBeams( ...
    numBeams, ...
    maxBeamFootprintDiameter, ...
    beamRadius, ...
    beamSpacing, ...
    beamMaxGain_dBi, ...
    beam3dBWidth_deg, ...
    beamEIRPDensity_dBW_per_MHz, ...
    channelBandwidth_Hz ...
);

for beamIndex = 1:numBeams
    SatelliteNode.addBeam(Beams(beamIndex));
end


%% ==================== 3. UT 생성 ====================

UTs = UTFactory.createUTs(Beams, numUTs);

targetUT = UTs(targetUTId);

targetBeamId = targetUT.AssociatedBeamId;
targetBeam = SatelliteNode.Beams(targetBeamId);


%% ==================== 4. APJ 생성 ====================

APJNode = APJFactory.createAPJ( ...
    UTs, ...
    Beams, ...
    targetUTId, ...
    targetJammerDistance ...
);


%% ==================== 5. Calibration ====================
%
% 목적:
%
%   Target UT와 APJ가 동일한 Target Beam 신호를 수신한다고 가정
%
%   - Co-channel interference 없음
%   - APJ jamming 없음
%
% 상태에서
%
%   모든 Service Channel에 대해
%
%   Actual Target UT SNR
%   APJ Observed SNR
%
% 을 계산한다.
%
% 두 위치에서 발생하는 SNR 차이를 통해
% APJ pseudo HARQ threshold의 후보를 결정한다.
%


actualUTSNR_dB = zeros(1, numChannels);
estimatedAPJSNR_dB = zeros(1, numChannels);

snrDifference_dB = zeros(1, numChannels);


%% ==================== 6. Geometry ====================

targetUTDistance_m = ...
    targetUT.distanceTo(SatelliteNode);

apjDistance_m = ...
    APJNode.distanceTo(SatelliteNode);


fprintf("  Target UT ID             : %d\n", targetUT.Id);
fprintf("  Target Beam ID           : %d\n", targetBeamId);

fprintf("  Target UT Position       : (%.3f, %.3f, %.3f) km\n", ...
    targetUT.Position(1) / 1e3, ...
    targetUT.Position(2) / 1e3, ...
    targetUT.Position(3) / 1e3);

fprintf("  APJ Position             : (%.3f, %.3f, %.3f) km\n", ...
    APJNode.Position(1) / 1e3, ...
    APJNode.Position(2) / 1e3, ...
    APJNode.Position(3) / 1e3);

fprintf("  Target UT Distance       : %.3f km\n", ...
    targetUTDistance_m / 1e3);

fprintf("  APJ Distance             : %.3f km\n", ...
    apjDistance_m / 1e3);

fprintf("  Target UT - APJ Distance : %.3f km\n", ...
    targetUT.distanceTo(APJNode) / 1e3);


%% ==================== 7. Channel별 SNR 계산 ====================

for channelIndex = 1:numChannels

    %% ==================== Channel Frequency ====================

    centerFrequency_Hz = ...
        serviceBandStart_Hz ...
        + (channelIndex - 0.5) * channelSpacing_Hz;


    %% ============================================================
    % Target UT
    %% ============================================================

    lambda = 3e8 / centerFrequency_Hz;


    % Path Gain
    targetUTPathGain = ...
        (lambda / (4 * pi * targetUTDistance_m))^2;


    % Beam Tx Power
    txPower_W = ...
        10^((targetBeam.TxPower_dBm - 30) / 10);


    % Target Beam -> Target UT Gain
    targetUTTxGain_dBi = ...
        targetBeam.calculateTxGain( ...
            SatelliteNode, ...
            targetUT.Position, ...
            centerFrequency_Hz ...
        );

    targetUTTxGain_linear = ...
        10^(targetUTTxGain_dBi / 10);


    % UT Rx Gain
    targetUTRxGain_linear = ...
        10^(targetUT.RxGain_dBi / 10);


    % Desired Power @ UT
    targetUTDesiredPower_W = ...
        txPower_W ...
        * targetUTTxGain_linear ...
        * targetUTRxGain_linear ...
        * targetUTPathGain;


    % Noise @ UT
    targetUTNoiseFigure_linear = ...
        10^(targetUT.NoiseFigure_dB / 10);

    targetUTNoisePower_W = ...
        targetUT.k ...
        * targetUT.NoiseTemperature ...
        * channelBandwidth_Hz ...
        * targetUTNoiseFigure_linear;


    % Interference-Free SNR @ UT
    actualUTSNR_dB(channelIndex) = ...
        10 * log10( ...
            targetUTDesiredPower_W / ...
            targetUTNoisePower_W ...
        );


    %% ============================================================
    % APJ
    %% ============================================================

    % Path Gain
    apjPathGain = ...
        (lambda / (4 * pi * apjDistance_m))^2;


    % Target Beam -> APJ Gain
    apjTxGain_dBi = ...
        targetBeam.calculateTxGain( ...
            SatelliteNode, ...
            APJNode.Position, ...
            centerFrequency_Hz ...
        );

    apjTxGain_linear = ...
        10^(apjTxGain_dBi / 10);


    % APJ Rx Gain
    apjRxGain_linear = ...
        10^(APJNode.RxGain_dBi / 10);


    % Desired Power @ APJ
    apjDesiredPower_W = ...
        txPower_W ...
        * apjTxGain_linear ...
        * apjRxGain_linear ...
        * apjPathGain;


    % Noise @ APJ
    apjNoiseFigure_linear = ...
        10^(APJNode.NoiseFigure_dB / 10);

    apjNoisePower_W = ...
        APJNode.k ...
        * APJNode.NoiseTemperature ...
        * channelBandwidth_Hz ...
        * apjNoiseFigure_linear;


    % Interference-Free SNR @ APJ
    estimatedAPJSNR_dB(channelIndex) = ...
        10 * log10( ...
            apjDesiredPower_W / ...
            apjNoisePower_W ...
        );


    %% ==================== Difference ====================

    snrDifference_dB(channelIndex) = ...
        estimatedAPJSNR_dB(channelIndex) ...
        - actualUTSNR_dB(channelIndex);

end


%% ==================== 8. 통계 ====================

meanActualUTSNR_dB = ...
    mean(actualUTSNR_dB);

meanEstimatedAPJSNR_dB = ...
    mean(estimatedAPJSNR_dB);

meanDifference_dB = ...
    mean(snrDifference_dB);

medianDifference_dB = ...
    median(snrDifference_dB);

minimumDifference_dB = ...
    min(snrDifference_dB);

maximumDifference_dB = ...
    max(snrDifference_dB);

maeDifference_dB = ...
    mean(abs(snrDifference_dB));


%% ==================== 9. Threshold Calibration ====================
%
% Target UT ACK 기준:
%
%   SINR_UT >= sinrThreshold_dB
%
% 만약 APJ가 평균적으로
%
%   SINR_APJ = SINR_UT + delta
%
% 형태로 관측한다면,
%
% APJ threshold는
%
%   gamma_APJ = gamma_UT + delta
%
% 로 보정할 수 있다.
%

calibratedThreshold_dB = ...
    sinrThreshold_dB ...
    + meanDifference_dB;


%% ==================== 10. 결과 출력 ====================

fprintf("\n");
fprintf("============================================================\n");
fprintf("APJ SINR Threshold Calibration Summary\n");
fprintf("============================================================\n");

fprintf("  Number of Channels       : %d\n", numChannels);

fprintf("\n");
fprintf("  [Target UT]\n");
fprintf("    SINR Threshold         : %.3f dB\n", ...
    sinrThreshold_dB);

fprintf("    Mean SNR               : %.3f dB\n", ...
    meanActualUTSNR_dB);


fprintf("\n");
fprintf("  [APJ]\n");
fprintf("    Mean Estimated SNR     : %.3f dB\n", ...
    meanEstimatedAPJSNR_dB);


fprintf("\n");
fprintf("  [APJ - Target UT SNR Difference]\n");

fprintf("    Mean Difference        : %+.3f dB\n", ...
    meanDifference_dB);

fprintf("    Median Difference      : %+.3f dB\n", ...
    medianDifference_dB);

fprintf("    Minimum Difference     : %+.3f dB\n", ...
    minimumDifference_dB);

fprintf("    Maximum Difference     : %+.3f dB\n", ...
    maximumDifference_dB);

fprintf("    Mean Absolute Diff.    : %.3f dB\n", ...
    maeDifference_dB);


fprintf("\n");
fprintf("  [Threshold Calibration]\n");

fprintf("    Target UT Threshold    : %.3f dB\n", ...
    sinrThreshold_dB);

fprintf("    Mean SNR Offset        : %+.3f dB\n", ...
    meanDifference_dB);

fprintf("    Calibrated APJ Thresh. : %.3f dB\n", ...
    calibratedThreshold_dB);


fprintf("\n");
fprintf("  Calibration Rule:\n");

fprintf("    gamma_APJ = gamma_UT + Mean(SNR_APJ - SNR_UT)\n");

fprintf("============================================================\n");


%% ==================== 11. Channel별 결과 ====================

fprintf("\n");
fprintf("============================================================\n");
fprintf("Per-Channel APJ SNR Calibration\n");
fprintf("============================================================\n");

for channelIndex = 1:numChannels

    fprintf( ...
        "  CH %2d | UT: %7.3f dB | APJ: %7.3f dB | Difference: %+7.3f dB\n", ...
        channelIndex, ...
        actualUTSNR_dB(channelIndex), ...
        estimatedAPJSNR_dB(channelIndex), ...
        snrDifference_dB(channelIndex) ...
    );

end

fprintf("============================================================\n");