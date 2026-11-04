clc;
clear;
close all;

env;

fprintf("============================================================\n");
fprintf("Interference-Free SNR Threshold Calibration\n");
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


%% ==================== 4. Calibration ====================
%
% 목적:
%
%   APJ 없음
%   Co-channel interference 없음
%
% 상태에서
%
%   모든 UT × 모든 Service Channel
%
% 의 SNR을 계산한다.
%
% 이를 통해 "정상 링크의 최저 SNR"을 찾는다.
%


allSNR_dB = zeros(numel(UTs), numChannels);


% Worst-case 기록
minimumSNR_dB = inf;

worstUTId = -1;
worstBeamId = -1;
worstChannelId = -1;

worstDistance_m = 0;
worstTxGain_dBi = 0;
worstRxPower_dBm = 0;


for utIndex = 1:numel(UTs)

    ut = UTs(utIndex);

    beamId = ut.AssociatedBeamId;
    beam = SatelliteNode.Beams(beamId);


    %% Satellite -> UT 거리
    distance_m = ut.distanceTo(SatelliteNode);


    for channelIndex = 1:numChannels

        %% ==================== Channel Frequency ====================
        %
        % 기존 Service Channel 생성 방식:
        %
        % f_k = serviceBandStart_Hz
        %       + (k - 0.5) * channelSpacing_Hz
        %

        centerFrequency_Hz = ...
            serviceBandStart_Hz ...
            + (channelIndex - 0.5) * channelSpacing_Hz;


        %% ==================== Path Gain ====================

        lambda = 3e8 / centerFrequency_Hz;

        pathGain = ...
            (lambda / (4 * pi * distance_m))^2;


        %% ==================== Beam Tx Power ====================

        txPower_W = ...
            10^((beam.TxPower_dBm - 30) / 10);


        %% ==================== Beam Tx Gain ====================

        txGain_dBi = ...
            beam.calculateTxGain( ...
                SatelliteNode, ...
                ut.Position, ...
                centerFrequency_Hz ...
            );

        txGain_linear = ...
            10^(txGain_dBi / 10);


        %% ==================== UT Rx Gain ====================

        rxGain_linear = ...
            10^(ut.RxGain_dBi / 10);


        %% ==================== Desired Received Power ====================

        desiredPower_W = ...
            txPower_W ...
            * txGain_linear ...
            * rxGain_linear ...
            * pathGain;

        desiredPower_dBm = ...
            10 * log10(desiredPower_W) + 30;


        %% ==================== Noise Power ====================

        noiseFigure_linear = ...
            10^(ut.NoiseFigure_dB / 10);

        noisePower_W = ...
            ut.k ...
            * ut.NoiseTemperature ...
            * channelBandwidth_Hz ...
            * noiseFigure_linear;


        %% ==================== Interference-Free SNR ====================

        SNR_dB = ...
            10 * log10( ...
                desiredPower_W / noisePower_W ...
            );


        allSNR_dB(utIndex, channelIndex) = SNR_dB;


        %% ==================== Worst Case 갱신 ====================

        if SNR_dB < minimumSNR_dB

            minimumSNR_dB = SNR_dB;

            worstUTId = ut.Id;
            worstBeamId = beamId;
            worstChannelId = channelIndex;

            worstDistance_m = distance_m;
            worstTxGain_dBi = txGain_dBi;
            worstRxPower_dBm = desiredPower_dBm;

        end

    end

end


%% ==================== 5. 전체 통계 ====================

snrSamples_dB = allSNR_dB(:);

maximumSNR_dB = max(snrSamples_dB);
meanSNR_dB = mean(snrSamples_dB);
medianSNR_dB = median(snrSamples_dB);

percentile1_dB = prctile(snrSamples_dB, 1);
percentile5_dB = prctile(snrSamples_dB, 5);


%% ==================== 6. Threshold 후보 ====================
%
% 정상 링크를 "무조건 ACK"시키고 싶다면
%
% threshold < minimum interference-free SNR
%
% 이어야 한다.
%
% floating-point / 향후 미세한 파라미터 차이를 고려해서
% minimum SNR 바로 아래에 작은 margin을 둔다.
%

safetyMargin_dB = 0.1;

strictThreshold_dB = ...
    minimumSNR_dB - safetyMargin_dB;


%% ==================== 7. 결과 출력 ====================

fprintf("\n");
fprintf("============================================================\n");
fprintf("Interference-Free SNR Calibration Summary\n");
fprintf("============================================================\n");

fprintf("  Number of UTs            : %d\n", numel(UTs));
fprintf("  Number of Channels       : %d\n", numChannels);
fprintf("  Number of Samples        : %d\n", numel(snrSamples_dB));

fprintf("\n");
fprintf("  [SNR Statistics]\n");
fprintf("    Minimum SNR            : %.4f dB\n", minimumSNR_dB);
fprintf("    Maximum SNR            : %.4f dB\n", maximumSNR_dB);
fprintf("    Mean SNR               : %.4f dB\n", meanSNR_dB);
fprintf("    Median SNR             : %.4f dB\n", medianSNR_dB);
fprintf("    1%% Percentile          : %.4f dB\n", percentile1_dB);
fprintf("    5%% Percentile          : %.4f dB\n", percentile5_dB);

fprintf("\n");
fprintf("  [Worst Interference-Free Link]\n");
fprintf("    UT                     : %d\n", worstUTId);
fprintf("    Beam                   : %d\n", worstBeamId);
fprintf("    Channel                : %d\n", worstChannelId);
fprintf("    Satellite Distance     : %.3f km\n", worstDistance_m / 1e3);
fprintf("    Beam Tx Gain           : %.3f dBi\n", worstTxGain_dBi);
fprintf("    Received Power         : %.3f dBm\n", worstRxPower_dBm);
fprintf("    SNR                    : %.4f dB\n", minimumSNR_dB);

fprintf("\n");
fprintf("  [Threshold Calibration]\n");
fprintf("    Safety Margin          : %.2f dB\n", safetyMargin_dB);
fprintf("    Strict ACK Threshold   : %.2f dB\n", strictThreshold_dB);

fprintf("\n");
fprintf("  Condition:\n");
fprintf("    Threshold <= %.2f dB\n", strictThreshold_dB);
fprintf("    guarantees all tested interference-free links are ACK.\n");

fprintf("============================================================\n");


%% ==================== 8. UT별 Interference-Free SNR 출력 ====================

fprintf("\n");
fprintf("============================================================\n");
fprintf("Per-UT Interference-Free SNR Range\n");
fprintf("============================================================\n");

for utIndex = 1:numel(UTs)

    utMinimumSNR_dB = min(allSNR_dB(utIndex, :));
    utMaximumSNR_dB = max(allSNR_dB(utIndex, :));

    fprintf( ...
        "  UT %2d | Min: %7.3f dB | Max: %7.3f dB\n", ...
        UTs(utIndex).Id, ...
        utMinimumSNR_dB, ...
        utMaximumSNR_dB ...
    );

end

fprintf("============================================================\n");