classdef TransmissionRecord
    properties
        packet
        slot
        txChannel
        rxChannel
        success
        ack
    end

    methods
        function obj = TransmissionRecord(packet, slot, txChannel, rxChannel, success, ack)
            obj.packet = packet;
            obj.slot = slot;
            obj.txChannel = txChannel;
            obj.rxChannel = rxChannel;
            obj.success = success;
            obj.ack = ack;
        end

    end


end