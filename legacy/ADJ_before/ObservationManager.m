classdef ObservationManager < handle
    properties
        Owner
        NumChannels %Observation 크기 결정(k)

        HistoryLength %Waterfall 길이 (phi)
        
        CurrentObservation %o_t (1*k)
        History %O_t (phi * k)
    end

    methods
        function obj = ObservationManager(owner, numChannels, phi)
            obj.Owner = owner; % 관측 주체

            obj.NumChannels = numChannels;
            obj.HistoryLength = phi;

            % 관측 정보 초기화
            obj.CurrentObservation = zeros(1, obj.NumChannels);
            obj.History = zeros(phi, obj.NumChannels);
        end


        % ========== 채널 센싱 ==========
        function observation = observe(obj, channels, UTs)
            obj.CurrentObservation = zeros(1, obj.NumChannels);
            
            for channelIndex = 1:numel(channels)
                obj.CurrentObservation(channelIndex) = obj.measureChannelPower_dBm(channels(channelIndex), UTs);
            end

            % 히스토리 저장
            obj.History = [
                obj.CurrentObservation
                obj.History(1:end-1, :)
                ];

            observation = obj.History;

        end

        function totalPower_dBm = measureChannelPower_dBm(obj, channel, UTs)
            totalPower_W = 0;

            centerFreq_Hz = channel.CenterFrequency_Hz;
            bandwidth_Hz = channel.Bandwidth_Hz;

            packets = channel.getPackets();

            for packetIndex = 1:numel(packets)
                packet = packets(packetIndex);


                % 자신의 송신 신호 제외
                if (packet.SourceId == obj.Owner.Id) && (packet.SourceType == obj.Owner.Type)
                    continue;
                end

                % Target UT의 송신 신호 제외
                if obj.Owner.Type == NodeType.APJ && ...
                   packet.SourceType == NodeType.UT && ...
                   packet.SourceId == obj.Owner.TargetUTId
                    continue;
                end

                sourceNode = UTs(packet.SourceId);

                % 수신 전력 측정
                receivedPower_W = obj.calculateReceivedPower(sourceNode, centerFreq_Hz);
                totalPower_W = totalPower_W + receivedPower_W;

            end

            % 잡음 전력 추가
            noisePower_W = obj.calculateNoisePower(bandwidth_Hz);
            totalPower_W = totalPower_W + noisePower_W;

            totalPower_dBm = 10*log10(totalPower_W) + 30;
        end

        % ========== 개별 신호 수신 전력 ==========
        function receivedPower_W = calculateReceivedPower(obj, sourceNode, centerFreq_Hz)
            lambda = 3e8 / centerFreq_Hz;
            distance = obj.Owner.distanceTo(sourceNode);

            h = (lambda / (4*pi*distance)) ^ 2;
            txPower_W = 10^((sourceNode.TxPower_dBm - 30) / 10);

            receivedPower_W = txPower_W * h;

        end

        % ========== 잡음 전력 ==========
        function noisePower_W = calculateNoisePower(obj, bandwidth_Hz)
            noiseFigure_W = 10^(obj.Owner.NoiseFigure_dB/10);
            noisePower_W = obj.Owner.k * obj.Owner.NoiseTemperature * bandwidth_Hz * noiseFigure_W;
        end

    end


end