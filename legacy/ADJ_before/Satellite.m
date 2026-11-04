classdef Satellite < Node
    properties
        AssociatedUTId
        Threshold

        SatelliteRxGain_dBi      % Set-1
        SatelliteGOverT_dB       % Set-1
        SystemNoiseTemperature_K
    end

    methods
        % ========== 생성자 ========== %
        function obj = Satellite(id, position, txPower_dBm, associatedUTId, threshold, satelliteRxGain_dBi, satelliteGOverT_dB)
            obj@Node(id, NodeType.Satellite, position, txPower_dBm);
            obj.SatelliteRxGain_dBi = satelliteRxGain_dBi;
            obj.SatelliteGOverT_dB = satelliteGOverT_dB;

            obj.SystemNoiseTemperature_K = 10.^((obj.SatelliteRxGain_dBi - obj.SatelliteGOverT_dB)/10);
            obj.AssociatedUTId = associatedUTId;
            obj.Threshold = threshold;
        end
    
        % ========== HARQ Perform ========== %
        function performHARQ(obj, ServiceChannels, ControlChannels, UTs)
            myPacket = obj.findMyPacket(ServiceChannels);

            % 없을 일은 없지만 혹시 모를 오류 대비용
            if isempty(myPacket)
                return;
            end

            selectedChannel = myPacket.ChannelId;
            packets = ServiceChannels(selectedChannel).getPackets();
            interferencePackets = packets;
            interferencePackets([packets.SourceId] == myPacket.SourceId) = [];

            centerFrequency_Hz = ServiceChannels(selectedChannel).CenterFrequency_Hz;
            bandWidth_Hz = ServiceChannels(selectedChannel).Bandwidth_Hz;
            
            % SINR 계산
            sinr = obj.calculateSINR(myPacket, interferencePackets, UTs, centerFrequency_Hz, bandWidth_Hz);


            %HARQ 패킷 생성 후 Control Channel에 전송
            packetType = obj.generateHARQFeedback(sinr);
            harqPacket = Packet(packetType, NodeType.Satellite, obj.Id, NodeType.UT, myPacket.SourceId, ControlChannels, selectedChannel);

            ControlChannels(selectedChannel).addPacket(harqPacket);

        end



        % ========== HARQ Feedback ========== %
        function packetType = generateHARQFeedback(obj, sinr)
            if sinr >= obj.Threshold
                packetType = PacketType.ACK;
            else
                packetType = PacketType.NACK;
            end
        end


        % ========== SINR 계산 ========== % 
        function SINR_dB = calculateSINR(obj, targetPacket, interferencePackets, UTs, centerFrequency_Hz, bandWidth_Hz)

            % 안테나 이득
            G_ut_dBi = 0; %UT단말 안테나 이득(무지향성)
            Gt = 10^(G_ut_dBi / 10);
            Gr = 10^(obj.SatelliteRxGain_dBi/10);



            % 원하는 신호 전력 계산
            targetId = targetPacket.SourceId;
            targetTxPower_dBm = UTs(targetId).TxPower_dBm;
            targetTxPower_W = 10^((targetTxPower_dBm - 30) / 10);
            
            lambda = 3e8 / centerFrequency_Hz;
            distance = obj.distanceTo(UTs(targetId));

            h = (lambda / (4*pi*distance)) ^ 2;

            receivedPower_W = targetTxPower_W * h * Gt*Gr ;


            % 간섭 전력 합산
            interferencePower_W = 0;

            for i = 1:numel(interferencePackets)
                interferencePacket = interferencePackets(i);
                interferenceUTId = interferencePacket.SourceId;

                interferenceTxPower_dBm = UTs(interferenceUTId).TxPower_dBm;
                interferenceTxPower_W = 10^((interferenceTxPower_dBm - 30) / 10);
                
                interferenceDistance = obj.distanceTo(UTs(interferenceUTId));
                interferenceH = (lambda / (4 * pi * interferenceDistance)) ^ 2;
                interferencePower_W = interferencePower_W + interferenceTxPower_W * interferenceH * Gt*Gr;
            end




            % 잡음 전력
            % noisePower_dBm = -140;
            noisePower_W = obj.k * obj.SystemNoiseTemperature_K * bandWidth_Hz;
            % noisePower_dBm = 10*log10(noisePower_W) + 30;
            % noisePower_dBm


            %최종 SINR 계산
            SINR_linear = receivedPower_W / (interferencePower_W + noisePower_W);
            SINR_dB = 10 * log10(SINR_linear);

            % DebugHelper.printSINR(obj.Id, targetId, targetPacket.ChannelId, distance, receivedPower_W, interferencePower_W, noisePower_W, ...
            %     SINR_linear, SINR_dB, obj.Threshold);
        end
    end
end