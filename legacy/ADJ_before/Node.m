classdef (Abstract) Node < handle
    properties
        Id
        Type
        Position
        TxPower_dBm
        k = 1.380649e-23;
        NoiseTemperature = 290
        NoiseFigure_dB
    end

    methods
        % ========== 생성자 ==========
        function obj = Node(id, type, position, txPower_dBm)
            obj.Id = id;
            obj.Type = type;
            obj.Position = position(:);
            obj.TxPower_dBm = txPower_dBm;
        end


        % ========== 위치 반환 ==========
        function Position = getPosition(obj)
            Position = obj.Position; % Access the Position property
        end



        % ========== 거리차이 계산 ==========
        function distance = distanceTo(obj, otherNode)
            distance = norm(obj.Position - otherNode.Position);
        end

        
        % ========== 채널에서 자신한테 오는 패킷 찾기 ==========
        function myPacket = findMyPacket(obj, channels)

            myPacket = Packet.empty;

            for channelIndex = 1:numel(channels)
                packets = channels(channelIndex).getPackets();

                for packetIndex = 1:numel(packets)
                    packet = packets(packetIndex);

                    if packet.DestinationType == obj.Type && packet.DestinationId == obj.Id
                        myPacket = packet;
                        return;
                    end

                end
            end
        end

        % ==========================================


    end

end