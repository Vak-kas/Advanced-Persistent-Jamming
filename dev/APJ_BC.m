classdef APJ_BC < Node
    properties
        TargetUTId

        TxPower_dBm
        NoiseTemperature
        NoiseFigure_dB

        ObservedChannel
        PredictedChannel
        JammingChannel

        SINRThreshold_dB
        PredictedQValues


        ObservationManager
        StateManager
        Predictor
        % Agent
    end

    methods
        % ========== 생성자 ==========
        function obj = APJ_BC(id, position, targetUTId)
            env;

            obj@Node(id, NodeType.APJ, position);

            obj.TargetUTId = targetUTId;

            obj.TxPower_dBm = apjTxPower_dBm;
            obj.TxGain_dBi = apjTxGain_dBi;
            obj.RxGain_dBi = apjRxGain_dBi;

            obj.NoiseTemperature = noiseTemperature;
            obj.NoiseFigure_dB = apjNoiseFigure_dB;

            obj.SINRThreshold_dB = apjSINRThreshold_dB;

            obj.ObservedChannel = [];
            obj.PredictedChannel = [];
            obj.JammingChannel = [];

            obj.ObservationManager = ObservationManager(obj, numChannels);
            obj.StateManager = StateManager(numChannels, phi, observationMode);
            obj.Predictor = APJPredictor(obj);
            % obj.Agent = APJAgent(obj);


        end

        %% ========== Target UT가 사용하는 채널 찾기 ==========
        function observedChannel = findObservedChannel(obj, ServiceChannels)
        
            targetPacket = obj.findTargetPacket(ServiceChannels);
        
            if isempty(targetPacket)
                obj.ObservedChannel = [];
                observedChannel = [];
                return;
            end
        
            obj.ObservedChannel = targetPacket.ChannelId;
            observedChannel = obj.ObservedChannel;
        end



        %% ========== Target DATA Packet 찾기 ==========
        function targetPacket = findTargetPacket(obj, ServiceChannels)
        
            targetPacket = Packet.empty;
        
            for channelIndex = 1:numel(ServiceChannels)
        
                packets = ServiceChannels(channelIndex).getPackets();
        
                for packetIndex = 1:numel(packets)
        
                    packet = packets(packetIndex);
        
                    if packet.Type == PacketType.DATA && ...
                       packet.SourceType == NodeType.Satellite && ...
                       packet.DestinationType == NodeType.UT && ...
                       packet.DestinationId == obj.TargetUTId
        
                        targetPacket = packet;
                        return;
                    end
        
                end
            end
        end

        %% ========== APJ 위치에서 Target SINR 추정 ==========
        function estimatedSINR_dB = estimateTargetSINR(obj, ServiceChannels, Satellite)
        
            targetPacket = obj.findTargetPacket(ServiceChannels);
        
            if isempty(targetPacket)
                estimatedSINR_dB = [];
                return;
            end
        
            obj.ObservedChannel = targetPacket.ChannelId;
            packets = ServiceChannels(obj.ObservedChannel).getPackets();

            interferencePackets = packets;
            interferencePackets([packets.BeamId] == targetPacket.BeamId) = [];
        
            centerFrequency_Hz = ServiceChannels(obj.ObservedChannel).CenterFrequency_Hz;
            bandwidth_Hz = ServiceChannels(obj.ObservedChannel).Bandwidth_Hz;
            estimatedSINR_dB = obj.calculateObservedSINR(targetPacket, interferencePackets, Satellite, centerFrequency_Hz, bandwidth_Hz);
        end



        %% ========== SINR 계산 (다운링크: 위성이 송신원) ==========
        function SINR_dB = calculateObservedSINR(obj, targetPacket, interferencePackets, Satellite, centerFrequency_Hz, bandwidth_Hz)
             
            % 공통 값
            lambda = 3e8 / centerFrequency_Hz; % 파장
            distance = obj.distanceTo(Satellite); % Satellite -> 현재 UT 거리
            pathGain = (lambda / (4 * pi * distance))^2; % Free-Space Path Gain
            rxGain_linear = 10^(obj.RxGain_dBi / 10); % UT Rx Gain

            % 원하는 신호 전력 계산
            desiredBeamId = targetPacket.BeamId;
            desiredBeam = Satellite.Beams(desiredBeamId);
            desiredTxPower_dBm = desiredBeam.TxPower_dBm;
            desiredTxPower_W = 10^((desiredTxPower_dBm - 30) / 10);

            % desiredTxGain_dBi = desiredBeam.MaxTxGain_dBi;
            desiredTxGain_dBi = desiredBeam.calculateTxGain(Satellite, obj.Position, centerFrequency_Hz);
            desiredTxGain_linear = 10^(desiredTxGain_dBi / 10);
            desiredPower_W = desiredTxPower_W * desiredTxGain_linear * rxGain_linear * pathGain;

            % 간섭 전력 합산
            interferencePower_W = 0;
            interferenceGain_dBi = zeros(1, numel(interferencePackets));
            interferencePowerEach_W = zeros(1, numel(interferencePackets));

            for interferenceIndex = 1:numel(interferencePackets)
                interferencePacket = interferencePackets(interferenceIndex);
                interferingBeamId = interferencePacket.BeamId;
                interferingBeam =  Satellite.Beams(interferingBeamId);
                interferenceTxPower_dBm = interferingBeam.TxPower_dBm;
                interferenceTxPower_W = 10^((interferenceTxPower_dBm - 30) / 10);

                % interferenceTxGain_dBi = interferingBeam.MaxTxGain_dBi;
                interferenceTxGain_dBi = interferingBeam.calculateTxGain(Satellite, obj.Position, centerFrequency_Hz);
                interferenceTxGain_linear = 10^(interferenceTxGain_dBi / 10);
                interferenceReceivedPower_W = interferenceTxPower_W * interferenceTxGain_linear * rxGain_linear * pathGain;
                
                % 디버그용 저장
                interferenceGain_dBi(interferenceIndex) = interferenceTxGain_dBi;
                interferencePowerEach_W(interferenceIndex) = interferenceReceivedPower_W;
                
                interferencePower_W = interferencePower_W + interferenceReceivedPower_W; 
            end

             % 잡음 전력
            noiseFigure_linear = 10^(obj.NoiseFigure_dB / 10);
            noisePower_W = obj.k * obj.NoiseTemperature * bandwidth_Hz * noiseFigure_linear; % k T B F


            % 최종 SINR 계산
            SINR_linear = desiredPower_W / (interferencePower_W + noisePower_W);
            SINR_dB = 10 * log10(SINR_linear);

            % ========== Debug ==========

            % DebugHelper.printAPJSINREstimation(obj, targetPacket, centerFrequency_Hz, bandwidth_Hz, distance, ...
            %     desiredTxPower_dBm, desiredTxGain_dBi, desiredPower_W, interferencePackets, interferenceGain_dBi, interferencePowerEach_W, interferencePower_W, noisePower_W, SINR_dB);
        


        end

        %% ========== Pseudo HARQ 생성 ==========
        function packetType = generatePseudoHARQ(obj, estimatedSINR_dB)
        
            if isempty(estimatedSINR_dB)
                packetType = [];
                return;
            end
        
            if estimatedSINR_dB >= obj.SINRThreshold_dB
                packetType = PacketType.ACK;
            else
                packetType = PacketType.NACK;
            end
        
        end

        %% ========== Target Beam 정찰 ==========
        function [observedChannel, estimatedSINR_dB, pseudoHARQ] = observeTarget(obj, ServiceChannels, Satellite)
        
            % 1. Target UT가 실제 사용한 채널 확인
            observedChannel = obj.findObservedChannel(ServiceChannels);
            if isempty(observedChannel)
                estimatedSINR_dB = [];
                pseudoHARQ = [];
                return;
            end
        
            % 2. APJ 위치에서 Target 신호 SINR 추정
            estimatedSINR_dB = obj.estimateTargetSINR(ServiceChannels, Satellite);
        
            % 3. Pseudo ACK / NACK 생성
            pseudoHARQ = obj.generatePseudoHARQ(estimatedSINR_dB);
        end




    end
end