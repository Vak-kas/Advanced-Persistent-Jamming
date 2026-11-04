classdef APJ < Node
    properties
        TargetUTId

        ObservedChannel     % 실제 관측한 현재 UT 채널
        PredictedChannel    % Shadow DQN이 예측한 다음 채널
        JammingChannel      % 실제 공격한 채널

        Threshold

        ObservationManager
        Agent
    end

    methods
        % ========== 생성자 ========== %
        function obj = APJ(id, position, txPower_dBm, targetUTid, threshold, numChannels, phi)
            obj@Node(id, NodeType.APJ, position, txPower_dBm);
            obj.NoiseFigure_dB = 7;
            obj.TargetUTId = targetUTid;
            obj.ObservedChannel = [];
            obj.PredictedChannel = [];
            obj.JammingChannel = [];

            obj.Threshold = threshold;

            obj.ObservationManager = ObservationManager(obj, numChannels, phi);
            obj.Agent = APJAgent(obj);
        end


        % ========== Target UT가 사용중인 채널 찾기 ==========
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

        % ========== 채널에서 타킷 패킷 찾기 ==========
        function targetPacket = findTargetPacket(obj, ServiceChannels)

            targetPacket = Packet.empty;

            for channelIndex = 1:numel(ServiceChannels)
                packets = ServiceChannels(channelIndex).getPackets();

                for packetIndex = 1:numel(packets)
                    packet = packets(packetIndex);

                    if packet.SourceType == NodeType.UT && packet.SourceId == obj.TargetUTId
                        targetPacket = packet;
                        return;
                    end

                end
            end
        end


        % ========== HARQ 추정 ==========
        function estimatedACK = estimateHARQ(obj, ServiceChannels, UTs)
            estimatedSINR_dB = obj.estimateSINR(ServiceChannels, UTs);
            if isempty(estimatedSINR_dB)
                estimatedACK = [];
                return;
            end

            estimatedACK = (estimatedSINR_dB >=obj.Threshold);

        end

        % ========== SINR 추정 ==========
        function estimateSINR = estimateSINR(obj, ServiceChannels, UTs)
            targetPacket = obj.findTargetPacket(ServiceChannels);

            % 없을 일은 없지만 혹시 모를 오류 대비용
            if isempty(targetPacket)
                return;
            end

            packets = ServiceChannels(obj.ObservedChannel).getPackets();

            interferencePackets = packets;
            interferencePackets([packets.SourceId] == targetPacket.SourceId) = [];

            centerFrequency_Hz = ServiceChannels(obj.ObservedChannel).CenterFrequency_Hz;
            bandWidth_Hz = ServiceChannels(obj.ObservedChannel).Bandwidth_Hz;


            % SINR 계산
            estimateSINR = obj.calculateSINR(targetPacket, interferencePackets, UTs, centerFrequency_Hz, bandWidth_Hz);


        end

        % ========== SINR 계산 ========== % 
        function SINR_dB = calculateSINR(obj, targetPacket, interferencePackets, UTs, centerFrequency_Hz, bandWidth_Hz)

            % 원하는 신호 전력 계산
            targetId = targetPacket.SourceId;
            targetTxPower_dBm = UTs(targetId).TxPower_dBm;
            targetTxPower_W = 10^((targetTxPower_dBm - 30) / 10);
            
            lambda = 3e8 / centerFrequency_Hz;
            distance = obj.distanceTo(UTs(targetId));

            h = (lambda / (4*pi*distance)) ^ 2;

            receivedPower_W = targetTxPower_W * h;


            % 간섭 전력 합산
            interferencePower_W = 0;

            for i = 1:numel(interferencePackets)
                interferencePacket = interferencePackets(i);
                interferenceUTId = interferencePacket.SourceId;

                interferenceTxPower_dBm = UTs(interferenceUTId).TxPower_dBm;
                interferenceTxPower_W = 10^((interferenceTxPower_dBm - 30) / 10);
                
                interferenceDistance = obj.distanceTo(UTs(interferenceUTId));
                interferenceH = (lambda / (4 * pi * interferenceDistance)) ^ 2;
                interferencePower_W = interferencePower_W + interferenceTxPower_W * interferenceH;
            end



            % 잡음 전력
            noiseFigure_W = 10^(obj.NoiseFigure_dB/10);
            noisePower_W = obj.k * obj.NoiseTemperature  * bandWidth_Hz * noiseFigure_W;


            %최종 SINR 계산
            SINR_linear = receivedPower_W / (interferencePower_W + noisePower_W);
            SINR_dB = 10 * log10(SINR_linear);

            % DebugHelper.printSINR(obj.Id, targetId, targetPacket.ChannelId, distance, receivedPower_W, interferencePower_W, noisePower_W, ...
            %     SINR_linear, SINR_dB, obj.Threshold);
        end


    end

end