classdef Packet
    properties
        Type %PacketTYpe

        SourceType %NodeType
        SourceId

        DestinationType %NodeType
        DestinationId

        BeamId 

        ChannelType %ChannelType
        ChannelId

        Payload
    end

    methods
        % ========== 생성자 ========== %
        function obj = Packet(type, sourceType, sourceId, destinationType, destinationId, beamId, channelType, channelId)
            obj.Type = type;
            obj.SourceType = sourceType;
            obj.SourceId = sourceId;
            
            obj.DestinationType = destinationType;
            obj.DestinationId = destinationId;

            obj.BeamId = beamId;

            obj.ChannelType = channelType;
            obj.ChannelId = channelId;

            obj.Payload = [];
        end


        % ========== Payload 설정 ==========
        function obj = setPayload(obj, payload)
            obj.Payload = payload;
        end


    end


end