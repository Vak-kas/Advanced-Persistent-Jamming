classdef APJ < Node
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
        Agent
    end

    methods
        %% ========== 생성자 ==========
        function obj = APJ(id, position, targetUTId)
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
            obj.PredictedQValues = [];

            % Full-Oracle Shadow DQN용
            obj.ObservationManager = ObservationManager(obj, numChannels);
            obj.StateManager = StateManager(numChannels, phi, observationMode);

            % Predictor가 아니라 DQN Agent
            obj.Agent = APJAgent(obj);
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
        %
        % [수정됨] targetUT 인자를 추가로 받는다. 자기 자신이 쏜
        % JAMMING 패킷을 이제 별도로 골라내서 계산에 반영하기 위함
        % (아래 calculateObservedSINR 참고).
        function estimatedSINR_dB = estimateTargetSINR( ...
                obj, ServiceChannels, Satellite, targetUT)

            targetPacket = obj.findTargetPacket(ServiceChannels);

            if isempty(targetPacket)
                estimatedSINR_dB = [];
                return;
            end

            obj.ObservedChannel = targetPacket.ChannelId;

            packets = ...
                ServiceChannels(obj.ObservedChannel).getPackets();

            % DATA 간섭: 자기 자신(Target) Beam이 아닌 DATA 패킷만
            dataPackets = packets([packets.Type] == PacketType.DATA);
            interferencePackets = dataPackets( ...
                [dataPackets.BeamId] ~= targetPacket.BeamId);

            % [수정] JAMMING 패킷은 Type으로 직접 골라낸다.
            % (재밍 패킷의 BeamId가 targetBeamId와 같게 설정돼 있어서,
            %  기존처럼 "targetPacket.BeamId와 같으면 제외"하는 필터를
            %  쓰면 자기 자신이 쏜 재밍인데도 "Target 자신의 신호"로
            %  오인되어 계산에서 통째로 빠지던 문제가 있었음.)
            jammingPackets = packets([packets.Type] == PacketType.JAMMING);

            centerFrequency_Hz = ...
                ServiceChannels( ...
                    obj.ObservedChannel).CenterFrequency_Hz;

            bandwidth_Hz = ...
                ServiceChannels( ...
                    obj.ObservedChannel).Bandwidth_Hz;

            estimatedSINR_dB = ...
                obj.calculateObservedSINR( ...
                    targetPacket, ...
                    interferencePackets, ...
                    jammingPackets, ...
                    Satellite, ...
                    targetUT, ...
                    centerFrequency_Hz, ...
                    bandwidth_Hz);
        end


        %% ========== SINR 계산 ==========
        %
        % [수정됨] jammingPackets, targetUT 인자 추가.
        % 자기 자신의 재밍이 Target UT 위치에 미치는 영향을 명시적으로
        % 더한다. 이때 거리는 obj.distanceTo(obj)(자기 자신, 0에 가까워
        % 발산)가 아니라 obj.distanceTo(targetUT)(APJ -> 실제 Target UT
        % 거리, targetJammerDistance로 배치 시점에 이미 알고 있는 값)를
        % 쓴다 — 이건 오라클이 아니라 재머 자신의 배치 파라미터라
        % 정당하게 쓸 수 있는 값.
        function SINR_dB = calculateObservedSINR( ...
                obj, ...
                targetPacket, ...
                interferencePackets, ...
                jammingPackets, ...
                Satellite, ...
                targetUT, ...
                centerFrequency_Hz, ...
                bandwidth_Hz)

            % 파장
            lambda = 3e8 / centerFrequency_Hz;

            % Satellite -> APJ 거리 (원하는 신호 / DATA 간섭 계산용,
            % 기존과 동일 — APJ 위치를 Target 위치의 근사치로 사용)
            distance = obj.distanceTo(Satellite);

            % FSPL 기반 path gain
            pathGain = ...
                (lambda / (4 * pi * distance))^2;

            rxGain_linear = ...
                10^(obj.RxGain_dBi / 10);


            %% ===== Desired Signal =====
            desiredBeamId = ...
                targetPacket.BeamId;

            desiredBeam = ...
                Satellite.Beams(desiredBeamId);

            desiredTxPower_dBm = ...
                desiredBeam.TxPower_dBm;

            desiredTxPower_W = ...
                10^((desiredTxPower_dBm - 30) / 10);

            desiredTxGain_dBi = ...
                desiredBeam.calculateTxGain( ...
                    Satellite, ...
                    obj.Position, ...
                    centerFrequency_Hz);

            desiredTxGain_linear = ...
                10^(desiredTxGain_dBi / 10);

            desiredPower_W = ...
                desiredTxPower_W * ...
                desiredTxGain_linear * ...
                rxGain_linear * ...
                pathGain;


            %% ===== DATA Interference =====
            interferencePower_W = 0;

            interferenceGain_dBi = ...
                zeros(1, numel(interferencePackets));

            interferencePowerEach_W = ...
                zeros(1, numel(interferencePackets));

            for interferenceIndex = ...
                    1:numel(interferencePackets)

                interferencePacket = ...
                    interferencePackets(interferenceIndex);

                interferingBeamId = ...
                    interferencePacket.BeamId;

                interferingBeam = ...
                    Satellite.Beams(interferingBeamId);

                interferenceTxPower_dBm = ...
                    interferingBeam.TxPower_dBm;

                interferenceTxPower_W = ...
                    10^((interferenceTxPower_dBm - 30) / 10);

                interferenceTxGain_dBi = ...
                    interferingBeam.calculateTxGain( ...
                        Satellite, ...
                        obj.Position, ...
                        centerFrequency_Hz);

                interferenceTxGain_linear = ...
                    10^(interferenceTxGain_dBi / 10);

                interferenceReceivedPower_W = ...
                    interferenceTxPower_W * ...
                    interferenceTxGain_linear * ...
                    rxGain_linear * ...
                    pathGain;

                interferenceGain_dBi(interferenceIndex) = ...
                    interferenceTxGain_dBi;

                interferencePowerEach_W(interferenceIndex) = ...
                    interferenceReceivedPower_W;

                interferencePower_W = ...
                    interferencePower_W + ...
                    interferenceReceivedPower_W;
            end


            %% ===== [신규] APJ 자기 자신의 재밍 (Target UT 위치 기준) =====
            jammingPower_W = 0;
            jammingPowerEach_W = zeros(1, numel(jammingPackets));

            if ~isempty(jammingPackets)

                distanceToTarget = obj.distanceTo(targetUT);

                jammingPathGain = ...
                    (lambda / (4 * pi * distanceToTarget))^2;

                jammerTxPower_W = ...
                    10^((obj.TxPower_dBm - 30) / 10);

                jammerTxGain_linear = ...
                    10^(obj.TxGain_dBi / 10);

                for jammingIndex = 1:numel(jammingPackets)

                    jammerReceivedPower_W = ...
                        jammerTxPower_W * ...
                        jammerTxGain_linear * ...
                        rxGain_linear * ...
                        jammingPathGain;

                    jammingPowerEach_W(jammingIndex) = jammerReceivedPower_W;
                    jammingPower_W = jammingPower_W + jammerReceivedPower_W;
                end
            end


            %% ===== Noise =====
            noiseFigure_linear = ...
                10^(obj.NoiseFigure_dB / 10);

            noisePower_W = ...
                obj.k * ...
                obj.NoiseTemperature * ...
                bandwidth_Hz * ...
                noiseFigure_linear;


            %% ===== SINR =====
            SINR_linear = ...
                desiredPower_W / ...
                (interferencePower_W + jammingPower_W + noisePower_W);

            SINR_dB = ...
                10 * log10(SINR_linear);


            % Debug
            % DebugHelper.printAPJSINREstimation( ...
            %     obj, ...
            %     targetPacket, ...
            %     centerFrequency_Hz, ...
            %     bandwidth_Hz, ...
            %     distance, ...
            %     desiredTxPower_dBm, ...
            %     desiredTxGain_dBi, ...
            %     desiredPower_W, ...
            %     interferencePackets, ...
            %     interferenceGain_dBi, ...
            %     interferencePowerEach_W, ...
            %     interferencePower_W, ...
            %     jammingPackets, ...
            %     jammingPowerEach_W, ...
            %     jammingPower_W, ...
            %     noisePower_W, ...
            %     SINR_dB);
        end


        %% ========== Pseudo HARQ 생성 ==========
        function packetType = generatePseudoHARQ( ...
                obj, estimatedSINR_dB)

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
        %
        % [수정됨] targetUT 인자 추가 — estimateTargetSINR에 그대로 전달.
        function [observedChannel, ...
                  estimatedSINR_dB, ...
                  pseudoHARQ] = ...
                observeTarget( ...
                    obj, ...
                    ServiceChannels, ...
                    Satellite, ...
                    targetUT)

            % 1. Target UT 실제 채널
            observedChannel = ...
                obj.findObservedChannel( ...
                    ServiceChannels);

            if isempty(observedChannel)
                estimatedSINR_dB = [];
                pseudoHARQ = [];
                return;
            end


            % 2. APJ 위치 기준 SINR (자기 재밍 반영)
            estimatedSINR_dB = ...
                obj.estimateTargetSINR( ...
                    ServiceChannels, ...
                    Satellite, ...
                    targetUT);


            % 3. Pseudo ACK / NACK
            pseudoHARQ = ...
                obj.generatePseudoHARQ( ...
                    estimatedSINR_dB);
        end
    end
end