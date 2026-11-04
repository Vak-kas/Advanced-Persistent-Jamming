classdef Channel < handle
    properties
        Id %채널 번호
        Type %ChannelType

        StartFrequency_Hz
        EndFrequency_Hz
        CenterFrequency_Hz %중심주파수

        Bandwidth_Hz

        Packets %Packet Array
    end

    methods
        % ========== 생성자 ========== %
        function obj = Channel(id, type, startFreq_Hz, endFreq_Hz)
            obj.Id = id;
            obj.Type = type;
            obj.StartFrequency_Hz = startFreq_Hz;
            obj.EndFrequency_Hz = endFreq_Hz;

            obj.Bandwidth_Hz = endFreq_Hz - startFreq_Hz;
            obj.CenterFrequency_Hz = (startFreq_Hz + endFreq_Hz) / 2;
            
            obj.Packets = Packet.empty;
        end

        % ========== 채널 초기화 ========== %
        function clearPacket(obj)
            obj.Packets = Packet.empty;
        end

        % ========== 채널 패킷 가져오기 ========== %
        function packets = getPackets(obj)
            packets = obj.Packets;
        end
            


        % ========== 패킷 추가 ========== %
        function addPacket(obj, packet)
            obj.Packets(end+1) = packet;
        end



    end
    

end