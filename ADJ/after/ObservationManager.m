classdef ObservationManager < handle
    properties
        NumObservations = 0
        Owner
        NumChannels  % k
        CurrentObservation % 현재 RF Sensing 결과 (1*k)

        % [신규] JAMMING 패킷 전력 계산용. 실험 스크립트에서 한 번 설정.
        %   Jammer   : JAMMING 패킷을 송신하는 노드 (APJ/APJ/IJ 등).
        %              비어 있으면 JAMMING 패킷은 센싱에서 제외(기존 동작).
        %   TargetUT : Owner가 재머 자신일 때, 자기 재밍이 Target UT에서
        %              받는 전력을 추정하기 위한 거리 기준. 비어 있으면
        %              재머 Owner는 자기 재밍을 센싱하지 않음.
        Jammer   = []
        TargetUT = []
    end

    methods
        % ========== 생성자 ==========
        function obj = ObservationManager(owner, numChannels)
            obj.Owner = owner;
            obj.NumChannels = numChannels;
            obj.CurrentObservation = zeros(1, obj.NumChannels);
        end

        % ========== 전체 Service Channel 센싱 ==========
        function observation = observe(obj, ServiceChannels, Satellite)
            observation = zeros(1, obj.NumChannels);

            for channelIndex = 1:obj.NumChannels
                observation(channelIndex) = ...
                    obj.measureChannelPower_dBm(ServiceChannels(channelIndex), Satellite);
            end

            obj.CurrentObservation = observation;
            obj.NumObservations = obj.NumObservations + 1;
        end

        % ========== 채널별 수신 전력 측정 ==========
        %
        % o_{n,k} = (co-channel DATA 간섭) + (JAMMING) + (noise)
        % 자기 자신의 desired signal은 제외.
        function totalPower_dBm = measureChannelPower_dBm(obj, channel, Satellite)
            totalPower_W = 0;
            centerFrequency_Hz = channel.CenterFrequency_Hz;
            packets = channel.getPackets();

            for packetIndex = 1:numel(packets)
                packet = packets(packetIndex);

                switch packet.Type

                    % ---------- DATA: 위성 빔 신호 ----------
                    case PacketType.DATA
                        beam = Satellite.Beams(packet.BeamId);

                        % 자신의 desired signal 제외
                        if obj.Owner.Type == NodeType.UT
                            if beam.Id == obj.Owner.AssociatedBeamId
                                continue;
                            end
                        elseif obj.Owner.Type == NodeType.APJ || ...
                               obj.Owner.Type == NodeType.IJ
                            % 재머는 Target UT 관측을 흉내내므로
                            % Target 빔 DATA는 desired signal로 간주하여 제외
                            if packet.DestinationId == obj.Owner.TargetUTId
                                continue;
                            end
                        end

                        totalPower_W = totalPower_W + ...
                            obj.calculateReceivedPower_W(beam, Satellite, centerFrequency_Hz);

                    % ---------- JAMMING: 재머 신호 ----------
                    case PacketType.JAMMING
                        if isempty(obj.Jammer)
                            continue;   % 재머 정보 없음 -> 제외 (기존 동작)
                        end

                        jammingPower_W = obj.calculateJammingPower_W(centerFrequency_Hz);

                        if ~isempty(jammingPower_W)
                            totalPower_W = totalPower_W + jammingPower_W;
                        end

                    % ---------- 그 외 (ACK/NACK 등) ----------
                    otherwise
                        continue;
                end
            end

            noisePower_W = obj.calculateNoisePower_W(channel.Bandwidth_Hz);
            totalPower_W = totalPower_W + noisePower_W;
            totalPower_dBm = 10 * log10(totalPower_W) + 30;
        end

        % ========== Beam 신호의 수신 전력 계산 ==========
        function receivedPower_W = calculateReceivedPower_W(obj, beam, Satellite, centerFrequency_Hz)
            lambda = 3e8 / centerFrequency_Hz;
            distance = obj.Owner.distanceTo(Satellite);
            pathGain = (lambda / (4 * pi * distance))^2;
            rxGain_linear = 10^(obj.Owner.RxGain_dBi / 10);
            txPower_W = 10^((beam.TxPower_dBm - 30) / 10);
            txGain_dBi = beam.calculateTxGain(Satellite, obj.Owner.Position, centerFrequency_Hz);
            txGain_linear = 10^(txGain_dBi / 10);

            receivedPower_W = txPower_W * txGain_linear * rxGain_linear * pathGain;
        end

        % ========== [신규] 재머 신호의 수신 전력 계산 ==========
        %
        % Owner가 UT       : 재머 -> Owner 거리 (실제 수신 전력)
        % Owner가 재머 자신 : Owner -> TargetUT 거리 (Target UT가 받을 전력 추정)
        %                    TargetUT 미설정이면 [] 반환 (자기 재밍 미센싱)
        % 식은 APJ.calculateObservedSINR의 jamming 항과 동일.
        function receivedPower_W = calculateJammingPower_W(obj, centerFrequency_Hz)
            receivedPower_W = [];
            jammer = obj.Jammer;

            if jammer.Id == obj.Owner.Id
                if isempty(obj.TargetUT)
                    return;
                end
                distance = obj.Owner.distanceTo(obj.TargetUT);
            else
                distance = obj.Owner.distanceTo(jammer);
            end

            if distance <= 0
                return;
            end

            lambda = 3e8 / centerFrequency_Hz;
            pathGain = (lambda / (4 * pi * distance))^2;
            txPower_W = 10^((jammer.TxPower_dBm - 30) / 10);
            txGain_linear = 10^(jammer.TxGain_dBi / 10);
            rxGain_linear = 10^(obj.Owner.RxGain_dBi / 10);

            receivedPower_W = txPower_W * txGain_linear * rxGain_linear * pathGain;
        end

        % ========== Noise Power 계산 ==========
        function noisePower_W = calculateNoisePower_W(obj, bandwidth_Hz)
            noiseFigure_linear = 10^(obj.Owner.NoiseFigure_dB / 10);
            noisePower_W = obj.Owner.k * obj.Owner.NoiseTemperature * bandwidth_Hz * noiseFigure_linear;
        end

        % ========== 현재 Observation 반환 ==========
        function observation = getCurrentObservation(obj)
            observation = obj.CurrentObservation;
        end
    end
end