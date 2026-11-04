classdef Packet
    properties
        Type %PacketTYpe

        SourceType %NodeType
        SourceId

        DestinationType %NodeType
        DestinationId

        ChannelType %ChannelType
        ChannelId
    end

    methods
        % ========== 생성자 ========== %
        function obj = Packet(type, sourceType, sourceId, destinationType, destinationId, channelType, channelId)
            obj.Type = type;
            obj.SourceType = sourceType;
            obj.SourceId = sourceId;
            
            obj.DestinationType = destinationType;
            obj.DestinationId = destinationId;

            obj.ChannelType = channelType;
            obj.ChannelId = channelId;
        end

    end


end