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


%%  ==================== Beam 생성 ====================
Beams = BeamFactory.createBeams(numBeams, maxBeamFootprintDiameter, beamRadius, beamSpacing, beamMaxGain_dBi, beam3dBWidth_deg, beamEIRPDensity_dBW_per_MHz, channelBandwidth_Hz);

for beamIndex = 1:numBeams
    SatelliteNode.addBeam(Beams(beamIndex));
end


%%  ==================== UT 생성 ====================
UTs = UTFactory.createUTs(Beams, numUTs);


%% ===================== APJ 생성 =====================
APJNode = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);


%% ==================== Time Slot 마다 수행 ====================
slotSuccessRatios = zeros(1, numTimeSlots);
targetACKResults = zeros(1, numTimeSlots);
targetSINRResults_dB = zeros(1, numTimeSlots);
totalACKCount = 0;
totalTransmissionCount = 0;

beamACKCount = zeros(1, numBeams);
beamNACKCount = zeros(1, numBeams);
actualTargetACKHistory = false(1, numTimeSlots);
pseudoTargetACKHistory = false(1, numTimeSlots);
actualTargetSINRHistory_dB = zeros(1, numTimeSlots);
estimatedTargetSINRHistory_dB = zeros(1, numTimeSlots);


timeSlot = TimeSlot();
% timeSlot = TimeSlotOO();
% qPolicyEvaluator = QPolicyShadowingEvaluator();
% timeSlot = TimeSlotOOQCompare(qPolicyEvaluator);
% timeSlot = TimeSlotNoAPJ();



for slotIndex = 1:numTimeSlots
    % [harqResults, sinrResults_dB, actualTargetACK, successRatio,
    % pseudoTargetACK, estimatedTargetSINR_dB] = timeSlot.run(slotIndex, UTs, SatelliteNode, APJNode, ServiceChannels, ControlChannels);
    [harqResults, sinrResults_dB, actualTargetACK, successRatio] = timeSlot.run(slotIndex, UTs, SatelliteNode, APJNode, ServiceChannels, ControlChannels);


    % 현재 Slot 결과 저장
    slotSuccessRatios(slotIndex) = successRatio;
    targetACKResults(slotIndex) = actualTargetACK;
    targetSINRResults_dB(slotIndex) = sinrResults_dB(targetUTId);

    % 전체 ACK 통계 누적
    for utIndex = 1:numel(UTs)
        if harqResults{utIndex} == PacketType.ACK
            totalACKCount = totalACKCount + 1;

            % Beam별 ACK
            beamACKCount(utIndex) = beamACKCount(utIndex) + 1;

        elseif harqResults{utIndex} == PacketType.NACK
            beamNACKCount(utIndex) = beamNACKCount(utIndex) +1;
        end


    end
    % actualTargetACKHistory(slotIndex) = actualTargetACK;
    % pseudoTargetACKHistory(slotIndex) = pseudoTargetACK;
    % actualTargetSINRHistory_dB(slotIndex) = sinrResults_dB(targetUTId);
    % estimatedTargetSINRHistory_dB(slotIndex) = estimatedTargetSINR_dB;
    %
    % totalTransmissionCount = totalTransmissionCount + numel(UTs);
end


%% ==================== Debug ====================
% DebugHelper.printSatelliteInfo(SatelliteNode);
% DebugHelper.printUTInfo(UTs, Beams, SatelliteNode);
% DebugHelper.printAPJInfo(APJNode, UTs, SatelliteNode);
% DebugHelper.printBeamUTAssociation(Beams, UTs);

% DebugHelper.printSimulationSummary(numTimeSlots, numel(UTs), totalACKCount, totalTransmissionCount, ...
%     slotSuccessRatios, targetACKResults, targetSINRResults_dB);
% DebugHelper.printPerBeamHARQSummary(beamACKCount, beamNACKCount);
% DebugHelper.printQValues(SatelliteNode.Beams(1).Agent, 1);
% DebugHelper.printBeamPolicySummary();
% DebugHelper.printCollisionSummary(numChannels);
% DebugHelper.printAPJPseudoHARQEvaluation(actualTargetACKHistory, pseudoTargetACKHistory, actualTargetSINRHistory_dB, estimatedTargetSINRHistory_dB);
DebugHelper.printAPJPredictionSummary(numel(ServiceChannels));
% DebugHelper.printBeamAPJQAgreementSummary();

% ===== qPolicyEvaluator는 TimeSlotOOQCompare를 쓸 때만 생성되므로,
%       지금(순수 TimeSlot 사용)은 인스턴스가 없어 호출하면 에러가 남 → 주석 처리 =====
% qPolicyEvaluator.printSummary();
% qPolicyEvaluator.printMarginAnalysisSummary();



%% ==================== Figure ====================
% FigureHelper.plotSystemDeployment(SatelliteNode, Beams, UTs, APJNode, maxBeamFootprintDiameter);
% FigureHelper.plotBeamAPJQMAE();
% FigureHelper.plotBeamAPJCosineSimilarity();
% FigureHelper.plotBeamAPJQCorrelation();

% ===== 마찬가지로 qPolicyEvaluator 인스턴스가 없으므로 주석 처리 =====
% qPolicyEvaluator.plotAll();