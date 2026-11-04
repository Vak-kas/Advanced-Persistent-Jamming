classdef Beam < handle
    properties
        Id

        % ========== Geometry ==========
        CenterPosition          % 지상 Beam 중심 [x y 0]
        Radius                  % Beam 반경 [m]

        % ========== Antenna ==========
        MaxTxGain_dBi           % 최대 Tx Gain
        Beamwidth3dB_deg        % 3 dB Beamwidth [deg]

        % ========== Transmission ==========
        TxPower_dBm
        SelectedChannel

        % ========== Association ==========
        AssociatedUTId

        % ========== DRL ==========
        StateManager
        Agent
    end

    methods
        % ========== 생성자 ==========
        function obj = Beam(id, centerPosition, radius, txPower_dBm, maxTxGain_dBi, beamwidth3dB_deg, associatedUTId)
            env;
            obj.Id = id;

            obj.CenterPosition = centerPosition;
            obj.Radius = radius;

            obj.MaxTxGain_dBi = maxTxGain_dBi;
            obj.Beamwidth3dB_deg = beamwidth3dB_deg;

            obj.TxPower_dBm = txPower_dBm;
            obj.SelectedChannel = 1;

            obj.AssociatedUTId = associatedUTId;

            obj.StateManager = StateManager(numChannels, phi, observationMode);
            obj.Agent = BeamAgent(obj);
        end

        % ========== 빔 중심 주파수 가져오기 ==========
        function position = getCenterPosition(obj)
            position = obj.CenterPosition;
        end

        % ========== Beam 중심으로부터 지상 거리 계산 ==========
        function distance = groundDistanceTo(obj, position)
            beamCenter = obj.CenterPosition(:);
            position = position(:);
            distance = norm(beamCenter(1:2) - position(1:2));
        end

        % ========== 특정 위치에 대한 Beam Tx Gain 계산 ==========
        function gain_dBi = calculateTxGain(obj, Satellite, targetPosition, centerFrequency_Hz)
        
            % 위치 벡터
            satellitePosition = Satellite.Position(:);
            beamCenterPosition = obj.CenterPosition(:);
            targetPosition = targetPosition(:);
        
            % Satellite -> Beam Center 방향
            beamDirection = beamCenterPosition - satellitePosition;
        
            % Satellite -> Target 방향
            targetDirection = targetPosition - satellitePosition;
        
        
            % Off-axis Angle 계산
            cosTheta = dot(beamDirection, targetDirection) / (norm(beamDirection) * norm(targetDirection));
        
            % Numerical error 방지
            cosTheta = max(-1, min(1, cosTheta));
            theta_rad = acos(cosTheta);
        
        
            % 3GPP TR 38.811 Section 6.4.1
            % Circular aperture antenna pattern
        
            c = 3e8;
        
            % Set-1 LEO-600 S-band:
            % Equivalent satellite antenna aperture = 2 m (diameter)
            apertureDiameter_m = 2.0;
            apertureRadius_m = apertureDiameter_m / 2;
        
            % Wave number
            k = 2 * pi * centerFrequency_Hz / c;
        
            % Bessel argument
            x = k * apertureRadius_m * sin(theta_rad);
        
        
            % Normalized antenna gain
            if abs(x) < 1e-8
                normalizedGain = 1;
            else
                normalizedGain = (2 * besselj(1, x) / x)^2;
            end
        
        
            % Maximum gain 적용
            maxGain_linear = 10^(obj.MaxTxGain_dBi / 10);
            gain_linear = maxGain_linear * normalizedGain;
            
            % Linear -> dBi
            gain_dBi = 10 * log10(max(gain_linear, realmin));
        
        end


        %% ========== UT Feedback 수신 및 State 업데이트 ==========
        function isACK = receiveFeedback(obj, ControlChannels, Satellite)
            selectedChannel = obj.SelectedChannel; % 이번 Slot에서 Beam이 사용한 채널
            packets = ControlChannels(selectedChannel).getPackets(); % 동일한 Control Channel 확인
        
            feedbackPacket = Packet.empty;
        
        
            % 자기 Beam의 Feedback 탐색
            for packetIndex = 1:numel(packets)
                packet = packets(packetIndex);

                if packet.SourceType == NodeType.UT && packet.DestinationType == NodeType.Satellite && packet.DestinationId == Satellite.Id && packet.BeamId == obj.Id
                   feedbackPacket = packet;
                    break;
                end
            end
        
            if isempty(feedbackPacket)
                warning("Beam:FeedbackNotFound", "Beam %d의 feedback packet을 찾지 못했습니다.", obj.Id);
                return;
            end
        
            if feedbackPacket.ChannelId ~= selectedChannel
                error("Beam:ChannelMismatch", "Beam %d: SelectedChannel=%d, FeedbackChannel=%d", obj.Id, selectedChannel, feedbackPacket.ChannelId);
            end
        
        
            % O / A / H 추출
            observation = feedbackPacket.Payload;
            action = feedbackPacket.ChannelId;
            harq = feedbackPacket.Type;
        
            % State 업데이트
            obj.StateManager.update(observation, action, harq);

            isACK = harq == PacketType.ACK;
        
        end


    end
end