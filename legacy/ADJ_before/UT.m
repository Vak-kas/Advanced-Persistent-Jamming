classdef UT < Node
    properties
        IsTarget = false
        SelectedChannel

        ChannelPattern       % 예: [1 3 5 7]
        PatternIndex         % 현재 패턴 위치

        ObservationManager
        Agent
    end

    methods
        % ========== 생성자 ========== %
        function obj = UT(id, position, txPower_dBm, isTarget, numChannels, phi)
            obj@Node(id, NodeType.UT, position, txPower_dBm);
            obj.IsTarget = isTarget;
            obj.SelectedChannel = 1;

            obj.NoiseFigure_dB = 7;
            
            patternLength = 5;
            obj.ChannelPattern = randperm(numChannels, patternLength);
            obj.PatternIndex = 1;

            obj.ObservationManager = ObservationManager(obj, numChannels, phi);
            obj.Agent = UTAgent(obj);
        end

        % ========== HARQ값 수신 ========== %
        function actualACK = receiveHARQFeedback(obj, ControlChannels)
            packet = obj.findMyPacket(ControlChannels);
            actualACK = (packet.Type == PacketType.ACK);
        end



    end
end