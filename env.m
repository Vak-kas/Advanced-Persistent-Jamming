%% ==================== Simulation Parameters ====================
simulationSeed = 3;
reconnaissanceDuration = 1500;
numTimeSlots =  3000;
observationMode = ObservationMode.O;

%% ==================== Channel Parameters ====================
numChannels = 10; % Number of service channels

% serviceBandStart_Hz = 1980e6;
% serviceBandEnd_Hz = 2010e6;
serviceBandStart_Hz = 2170e6;
serviceBandEnd_Hz   = 2200e6;

totalBandwidth_Hz = serviceBandEnd_Hz - serviceBandStart_Hz;
NumServiceChannels = numChannels;
channelSpacing_Hz = totalBandwidth_Hz / NumServiceChannels;
channelBandwidth_Hz = 360e3;


%% ==================== System Parameters ====================
numSatellites = 1; % Number of satellites
numUTs = 19; % Number of UTs
numAPJ = 1;% Number of APJs
targetUTId = 1;% Target UT ID (= first beam in the fixed decision order, paper Sec. 2.2)

%% ==================== Satellite Parameters ====================
satelliteAltitude = 600e3; % 위성 고도 600km

satelliteRxGain_dBi = 30;      % Set-1
satelliteGOverT_dB = 1.1;       % Set-1

% Earth / Satellite
earthRadius = 6378e3;
minSatelliteElevation_deg = 10; %각도 (10도)
minSatelliteElevation_rad = deg2rad(minSatelliteElevation_deg); % Minimum elevation angle [rad]
maxGroundCentralAngle_rad = acos(earthRadius / (earthRadius + satelliteAltitude) * cos(minSatelliteElevation_rad)) - minSatelliteElevation_rad;
satelliteCoverageRadius = earthRadius * maxGroundCentralAngle_rad; % 약 1760 km

%% ==================== Beam Parameters ====================
numBeams = numUTs;

beamDiameter = 50e3;
beamRadius = beamDiameter / 2;
beamSpacing = 40e3;


maxBeamFootprintDiameter = 1000e3;  % 3GPP TR 38.821 Table 4.2-2
maxBeamCenterRadius = (maxBeamFootprintDiameter / 2) - beamRadius;  % ≈ 475km

% 3GPP LEO-600 S-band
beamMaxGain_dBi = 30;
beam3dBWidth_deg = 4.4127;

% Satellite EIRP Density
beamEIRPDensity_dBW_per_MHz = 34;


%% ==================== UT Parameters ====================
%UT 전송 파워
utTxPower_dBm = 23;

noiseTemperature = 290;
noiseFigure_dB = 7;
utTxGain_dBi = 0;
utRxGain_dBi = 0;

sinrThreshold_dB = 12.5; % SINR Threshold



%% ==================== APJ Parameters ====================
% targetJammerDistance = 1e3; %10km %Target UT - APJ Distance
targetJammerDistance =1000;
apjTxPower_dBm = 56; % APJ 전송 파워

apjRxGain_dBi = 0;
apjTxGain_dBi = 0;
apjNoiseFigure_dB = 7;
apjSINRThreshold_dB = 12.5;

%% ==================== COMMON DRL Parameters ====================
phi = 10;

%% ==================== Beam DRL Parameters ====================
beamBatchSize = 128;

beamLearnRate = 0.001;
beamDiscountFactor = 0.8;

beamReplayBufferCapacity = 5000;


% Epsilon-greedy
beamEpsilon = 1.000;
beamEpsilonMin = 0.001;
beamEpsilonDecay = 0.997;

beamTargetUpdateFrequency = 100;


beamSuccessReward = 5;
beamFailureReward = -1;
beamRewardFunction = @(isACK) double(isACK) * beamSuccessReward + double(~isACK) * beamFailureReward;



%% ==================== APJ DRL Parameters ====================
apjBatchSize = 256;

apjLearnRate = 0.001;
apjDiscountFactor = 0.9;

apjReplayBufferCapacity = 5000;

% Epsilon-greedy
apjEpsilon = 0.0;
apjEpsilonMin = 0.0;
apjEpsilonDecay = 1.0;

apjTargetUpdateFrequency = 200;


apjSuccessReward = 5;
apjFailureReward = -1;
apjRewardFunction = @(targetACK) double(targetACK) * apjSuccessReward + double(~targetACK) * apjFailureReward;

%% ==================== Intelligent Jammer (DQN-IJ, Jing et al.) Parameters ====================
ijTxPower_dBm    = apjTxPower_dBm;
ijTxGain_dBi     = apjTxGain_dBi;
ijRxGain_dBi     = apjRxGain_dBi;
ijNoiseFigure_dB = apjNoiseFigure_dB;

ijJammingBudget = 2;   % 논문 Eq.(23)의 ϖ에 해당 — 연속 제약 없이 자유 2채널 조합

ijBatchSize            = 256;
ijLearnRate            = 0.001;
ijDiscountFactor       = 0.9;
ijReplayBufferCapacity = 5000;

ijEpsilon             = 1.000;
ijEpsilonMin          = 0.05;
ijEpsilonDecay        = 0.999;
ijTargetUpdateFrequency = 200;

ijSuccessReward = 5;
ijFailureReward = -1;
ijRewardFunction = @(attackSucceeded) double(attackSucceeded) * ijSuccessReward + double(~attackSucceeded) * ijFailureReward;



%% ==================== 변수 설정 ====================
utTxPower_W = 10^((utTxPower_dBm - 30) / 10); % Convert transmit power from dBm to Watts
% satelliteTxPower_W = 10^((satelliteTxPower_dBm - 30) / 10); % Convert satellite transmit power from dBm to Watts
apjTxPower_W = 10^((apjTxPower_dBm - 30) / 10); % Convert APJ transmit power from dBm to Watts

% ===== Satellite coverage geometry =====
% rng(simulationSeed);

% fprintf("apjLearnRate = %.6f\n", apjLearnRate);