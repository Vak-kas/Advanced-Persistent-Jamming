classdef Packet
    properties
        type
        size

        srcId
        dstId
        payload
    end

    methods

        % ========== 생성자 ==========
        function obj = Packet(type, srcId, dstId, payload)
            obj.type = type;
            obj.size = obj.calculatePacketSize();
            obj.srcId = srcId;
            obj.dstId = dstId;
            obj.payload = payload;
        end


        % ========== 패킷 사이즈 ==========
        function size = calculatePacketSize(obj)
            switch obj.type

                case PacketType.DATA
                    size = 1500;

                case PacketType.ACK
                    size = 64;

                case PacketType.NACK
                    size = 64;

                case PacketType.CONTROL
                    size = 128;

                otherwise
                    size = 0;

            end
        end

    end
end