classdef IntelligentJammer < Node
    properties
        TargetUTId

        TxPower_dBm
        NoiseTemperature
        NoiseFigure_dB

        JammingChannels   % 다음 슬롯에 투입될 재밍 채널 (직전 슬롯에서 결정)

        SINRThreshold_dB  % 실제 UT의 SINR 임계값(sinrThreshold_dB)과 동일하게
                          % 맞춤 — "실제 UT가 ACK/NACK 했을지"를 정확히
                          % 추정하려면 UT 자신의 임계값을 그대로 써야 함

        ObservationManager
        StateManager
        Agent
    end

    methods
        function obj = IntelligentJammer(id, position, targetUTId)
            env;

            obj@Node(id, NodeType.IJ, position);

            obj.TargetUTId = targetUTId;

            obj.TxPower_dBm = ijTxPower_dBm;
            obj.TxGain_dBi  = ijTxGain_dBi;
            obj.RxGain_dBi  = ijRxGain_dBi;

            obj.NoiseTemperature = noiseTemperature;
            obj.NoiseFigure_dB   = ijNoiseFigure_dB;

            obj.SINRThreshold_dB = sinrThreshold_dB;

            obj.JammingChannels = [];

            obj.ObservationManager = ObservationManager(obj, numChannels);

            % [수정] history length = phi (env). 원 논문 Eq.(22)는 phi=1(현재 슬롯만)이지만,
            % APJ와 동일한 관측 history를 주어 baseline을 강화한 버전. phi=1로 돌리려면
            % env의 phi가 아니라 여기와 IntelligentJammerAgent의 inputSize를 함께 1로.
            obj.StateManager = StateManager(numChannels, phi, ObservationMode.O);

            obj.Agent = IntelligentJammerAgent(obj);
        end

        %% ========== 자기 위치에서 채널별 에너지 센싱 (Eq. 22, Target 신호 제외) ==========
        function state = senseState(obj, ServiceChannels, Satellite)
            observation = obj.ObservationManager.observe(ServiceChannels, Satellite);
            obj.StateManager.updateObservation(observation);
            state = obj.StateManager.getState();
        end

        %% ========== Target UT가 실제로 사용 중인 DATA 패킷 찾기 ==========
        %
        % APJ.findTargetPacket과 동일한 방식(패킷 메타데이터로 Target의
        % 실제 채널 확인). RF 파워 센싱(senseState)과는 완전히 별개의,
        % Reward 계산 전용 경로.
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

        %% ========== 자기 재밍이 Target에 미치는 영향 추정 -> Pseudo HARQ ==========
        %
        % selectedChannels : 이번 슬롯 IJ가 "고른" 채널들.
        %
        % 실제로 물리적 재밍 패킷이 채널에 주입됐는지 여부와 무관하게,
        % 분석적으로(자기 Tx power/거리 기반) 재밍 전력을 계산해서 SINR을
        % 추정한다.
        %
        %   - Attack Phase : 실제 주입 결과와 사실상 동일한 값이 나옴
        %   - Dry-Run(정찰) 중 : 실제로는 채널에 아무것도 주입하지 않지만
        %     "만약 지금 재밍했다면"을 분석적으로 계산 -> Target 환경에는
        %     전혀 영향을 주지 않으면서도 의미 있는 학습 신호를 얻음
        function [estimatedSINR_dB, estimatedOutcome] = ...
                estimateAttackOutcome(obj, ServiceChannels, Satellite, targetUT, selectedChannels)

            targetPacket = obj.findTargetPacket(ServiceChannels);

            if isempty(targetPacket)
                estimatedSINR_dB = [];
                estimatedOutcome = [];
                return;
            end

            targetChannelId = targetPacket.ChannelId;

            packets = ServiceChannels(targetChannelId).getPackets();

            dataPackets = packets([packets.Type] == PacketType.DATA);
            interferencePackets = dataPackets( ...
                [dataPackets.BeamId] ~= targetPacket.BeamId);

            centerFrequency_Hz = ServiceChannels(targetChannelId).CenterFrequency_Hz;
            bandwidth_Hz = ServiceChannels(targetChannelId).Bandwidth_Hz;

            isJammingThisChannel = any(selectedChannels == targetChannelId);

            estimatedSINR_dB = obj.calculateHypotheticalSINR( ...
                targetPacket, interferencePackets, isJammingThisChannel, ...
                Satellite, targetUT, centerFrequency_Hz, bandwidth_Hz);

            if estimatedSINR_dB >= obj.SINRThreshold_dB
                estimatedOutcome = PacketType.ACK;
            else
                estimatedOutcome = PacketType.NACK;
            end
        end

        %% ========== 자기 재밍(분석적 가정)을 포함한 SINR 계산 ==========
        function SINR_dB = calculateHypotheticalSINR( ...
                obj, targetPacket, interferencePackets, isJammingThisChannel, ...
                Satellite, targetUT, centerFrequency_Hz, bandwidth_Hz)

            lambda = 3e8 / centerFrequency_Hz;

            % Satellite -> IJ 거리 (Desired/Interference 신호 계산용,
            % IJ 위치를 Target 위치의 근사치로 사용 — APJ와 동일 관례)
            distance = obj.distanceTo(Satellite);
            pathGain = (lambda / (4 * pi * distance))^2;
            rxGain_linear = 10^(obj.RxGain_dBi / 10);

            %% ===== Desired Signal =====
            desiredBeamId = targetPacket.BeamId;
            desiredBeam = Satellite.Beams(desiredBeamId);
            desiredTxPower_W = 10^((desiredBeam.TxPower_dBm - 30) / 10);
            desiredTxGain_dBi = desiredBeam.calculateTxGain( ...
                Satellite, obj.Position, centerFrequency_Hz);
            desiredTxGain_linear = 10^(desiredTxGain_dBi / 10);
            desiredPower_W = desiredTxPower_W * desiredTxGain_linear * ...
                rxGain_linear * pathGain;

            %% ===== DATA Interference =====
            interferencePower_W = 0;

            for interferenceIndex = 1:numel(interferencePackets)
                interferencePacket = interferencePackets(interferenceIndex);
                interferingBeam = Satellite.Beams(interferencePacket.BeamId);
                interferenceTxPower_W = 10^((interferingBeam.TxPower_dBm - 30) / 10);
                interferenceTxGain_dBi = interferingBeam.calculateTxGain( ...
                    Satellite, obj.Position, centerFrequency_Hz);
                interferenceTxGain_linear = 10^(interferenceTxGain_dBi / 10);
                interferenceReceivedPower_W = interferenceTxPower_W * ...
                    interferenceTxGain_linear * rxGain_linear * pathGain;

                interferencePower_W = interferencePower_W + interferenceReceivedPower_W;
            end

            %% ===== 자기 재밍 (분석적, Target UT 위치 기준) =====
            jammingPower_W = 0;

            if isJammingThisChannel

                distanceToTarget = obj.distanceTo(targetUT);
                jammingPathGain = (lambda / (4 * pi * distanceToTarget))^2;

                jammerTxPower_W = 10^((obj.TxPower_dBm - 30) / 10);
                jammerTxGain_linear = 10^(obj.TxGain_dBi / 10);

                jammingPower_W = jammerTxPower_W * jammerTxGain_linear * ...
                    rxGain_linear * jammingPathGain;
            end

            %% ===== Noise =====
            noiseFigure_linear = 10^(obj.NoiseFigure_dB / 10);
            noisePower_W = obj.k * obj.NoiseTemperature * bandwidth_Hz * noiseFigure_linear;

            %% ===== SINR =====
            SINR_linear = desiredPower_W / ...
                (interferencePower_W + jammingPower_W + noisePower_W);
            SINR_dB = 10 * log10(SINR_linear);
        end
    end
end