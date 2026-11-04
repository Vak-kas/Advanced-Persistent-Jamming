classdef UT < Node
    properties
        IsTarget = false

        TxPower_dBm
        NoiseTemperature
        NoiseFigure_dB

        AssociatedBeamId
        SINRThreshold_dB

        ObservationManager

    end

    methods
        %% ========== 생성자 ========== %
        function obj = UT(id, position)
            env;

            obj@Node(id, NodeType.UT, position);

            obj.IsTarget = targetUTId==id;



            obj.TxGain_dBi = utTxGain_dBi;
            obj.RxGain_dBi = utRxGain_dBi;
  
            obj.TxPower_dBm = utTxPower_dBm;
            obj.NoiseTemperature = noiseTemperature;
            obj.NoiseFigure_dB = noiseFigure_dB;

            
            obj.AssociatedBeamId = id;
            obj.SINRThreshold_dB = sinrThreshold_dB;

            obj.ObservationManager = ObservationManager(obj, numChannels);
            

        end

        %% ========== Service 채널에서 자신에게 오는 DATA 패킷 찾기 ==========
        function desiredPacket = findDesiredPacket(obj, ServiceChannels)        

            desiredPacket = Packet.empty;
        
            for channelIndex = 1:numel(ServiceChannels)
                packets = ServiceChannels(channelIndex).getPackets();
        
                for packetIndex = 1:numel(packets)
                    packet = packets(packetIndex);

                    if packet.Type == PacketType.DATA && packet.DestinationType == NodeType.UT && packet.DestinationId == obj.Id && packet.BeamId == obj.AssociatedBeamId
                        desiredPacket = packet;
                        return;
                    end
                end
            end
        end


        %% ========== HRAQ 수행 ==========
        function [packetType, SINR_dB] = performHARQ(obj, ServiceChannels, ControlChannels, Satellite, APJ)
            % [신규] 매 슬롯 RF 관측. DATA/JAMMING 패킷이 모두 주입된 뒤 호출되므로
            % 이 시점의 채널 상태(간섭 + 재밍 + 잡음)가 관측에 반영된다.
            % 관측 결과는 아래 HARQ 패킷 payload로 위성에 보고된다.
            obj.ObservationManager.observe(ServiceChannels, Satellite);

            desiredPacket = obj.findDesiredPacket(ServiceChannels);
            
            % 오류 대비용
            if isempty(desiredPacket)
                packetType = [];
                SINR_dB = [];
                return;
            end

            selectedChannel = desiredPacket.ChannelId;
            packets = ServiceChannels(selectedChannel).getPackets();

            interferencePackets = Packet.empty;
            jammingPackets = Packet.empty;
            
            for packetIndex = 1:numel(packets)
                packet = packets(packetIndex);

                if packet.Type == PacketType.DATA
                    if packet.BeamId ~= desiredPacket.BeamId
                        interferencePackets(end + 1) = packet;
                    end
                elseif packet.Type == PacketType.JAMMING
                    jammingPackets(end + 1) = packet;
                end
            end


            centerFrequency_Hz = ServiceChannels(selectedChannel).CenterFrequency_Hz;
            bandwidth_Hz = ServiceChannels(selectedChannel).Bandwidth_Hz;

            SINR_dB = obj.calculateSINR(desiredPacket, interferencePackets, jammingPackets, Satellite, APJ, centerFrequency_Hz, bandwidth_Hz);

            packetType = obj.generateHARQFeedback(SINR_dB);
            harqPacket = Packet(packetType, NodeType.UT, obj.Id, NodeType.Satellite, Satellite.Id, obj.AssociatedBeamId, ChannelType.Control, selectedChannel);
            harqPacket = harqPacket.setPayload(obj.ObservationManager.CurrentObservation);

            ControlChannels(selectedChannel).addPacket(harqPacket);
        end



        %% ========== HARQ Feedback 결정 ==========
        function packetType = generateHARQFeedback(obj, SINR_dB)
            if SINR_dB >= obj.SINRThreshold_dB
                packetType = PacketType.ACK;
            else
                packetType = PacketType.NACK;
            end
        end


        %% ========== Downlink SINR 계산 ==========
        function SINR_dB = calculateSINR(obj, desiredPacket, interferencePackets, jammingPackets, Satellite, ...
                APJ, centerFrequency_Hz, bandwidth_Hz)

            % 공통 값
            lambda = 3e8 / centerFrequency_Hz; % 파장
            satelliteDistance = obj.distanceTo(Satellite); % Satellite -> 현재 UT 거리
            satellitePathGain = (lambda / (4 * pi * satelliteDistance))^2; % Free-Space Path Gain
            rxGain_dBi = obj.RxGain_dBi;
            rxGain_linear = 10^(rxGain_dBi / 10); % UT Rx Gain


            % 원하는 신호 전력 계산
            desiredBeamId = desiredPacket.BeamId;
            desiredBeam = Satellite.Beams(desiredBeamId);
            desiredTxPower_dBm = desiredBeam.TxPower_dBm;
            desiredTxPower_W = 10^((desiredTxPower_dBm - 30) / 10);

            % desiredTxGain_dBi = desiredBeam.MaxTxGain_dBi;
            desiredTxGain_dBi = desiredBeam.calculateTxGain(Satellite, obj.Position, centerFrequency_Hz);
            desiredTxGain_linear = 10^(desiredTxGain_dBi / 10);
            desiredPower_W = desiredTxPower_W * desiredTxGain_linear * rxGain_linear * satellitePathGain;



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
                interferenceReceivedPower_W = interferenceTxPower_W * interferenceTxGain_linear * rxGain_linear * satellitePathGain;
                
                % 디버그용 저장
                interferenceGain_dBi(interferenceIndex) = interferenceTxGain_dBi;
                interferencePowerEach_W(interferenceIndex) = interferenceReceivedPower_W;
                
                interferencePower_W = interferencePower_W + interferenceReceivedPower_W;   % 딱 한 번만
            end

            % APJ Jamming Power
            jammingPower_W = 0;
            jammingPowerEach_W = zeros(1, numel(jammingPackets));
            jammingDistance = [];
            jammerTxPower_dBm = APJ.TxPower_dBm;
            jammerTxGain_dBi = APJ.TxGain_dBi;
            for jammingIndex = 1:numel(jammingPackets)
                jammingPacket = jammingPackets(jammingIndex);
        
                % APJ가 만든 JAMMING packet만 처리
                if jammingPacket.SourceType ~= NodeType.APJ && jammingPacket.SourceType ~= NodeType.IJ
                    continue;
                end
        
                % APJ -> 현재 UT 거리
                jammingDistance =  obj.distanceTo(APJ);
                jammingPathGain = (lambda / (4 * pi * jammingDistance))^2;
        
                % APJ 송신 전력
                jammerTxPower_W = 10^((jammerTxPower_dBm - 30) / 10);
        
                % APJ 송신 안테나 gain
                jammerTxGain_linear = 10^(jammerTxGain_dBi / 10);
        
                % UT에서 수신되는 재밍 전력
                jammerReceivedPower_W = jammerTxPower_W * jammerTxGain_linear * rxGain_linear * jammingPathGain;
                jammingPowerEach_W(jammingIndex) = jammerReceivedPower_W;
                jammingPower_W = jammingPower_W + jammerReceivedPower_W;

            end


            % 잡음 전력
            noiseFigure_linear = 10^(obj.NoiseFigure_dB / 10);
            noisePower_W = obj.k * obj.NoiseTemperature * bandwidth_Hz * noiseFigure_linear; % k T B F
            


            % 최종 SINR 계산
            SINR_linear = desiredPower_W / (interferencePower_W + jammingPower_W + noisePower_W);
            SINR_dB = 10 * log10(SINR_linear);



            if obj.IsTarget
               % DebugHelper.printSINRCalculation(obj.Id, desiredBeamId, desiredPacket.ChannelId, centerFrequency_Hz, bandwidth_Hz, satelliteDistance, desiredTxPower_dBm, desiredTxGain_dBi, rxGain_dBi, desiredPower_W, ... 
               %      interferencePackets, interferenceGain_dBi, interferencePowerEach_W, interferencePower_W, ...
               %      jammingPackets, jammingDistance, jammerTxPower_dBm, jammerTxGain_dBi, jammingPowerEach_W, jammingPower_W, ...
               %      noisePower_W, SINR_dB, obj.SINRThreshold_dB);
            end
        end



      
    end
end