classdef Signal
    properties
        type
        packet
        txPower

        txNodeId
        txRole

        txChannelId
        txPosition

        startTime_ms
        endTime_ms
    end

    methods
        % ========== 생성자 ==========
        function obj = Signal(type, packet, txPower, txNodeId, txRole, txChannelId, txPosition, startTime_ms, endTime_ms)

            obj.type = type;
            obj.packet = packet;
            obj.txPower = txPower;

            obj.txNodeId = txNodeId;
            obj.txRole = txRole;

            obj.txChannelId = txChannelId;
            obj.txPosition = txPosition;

            if nargin < 8 || isempty(startTime_ms)
                startTime_ms = 0;
            end

            if nargin < 9 || isempty(endTime_ms)
                endTime_ms = inf;
            end

            obj.startTime_ms = startTime_ms;
            obj.endTime_ms = endTime_ms;


        end
        

        % ========== 시그널 유효 시간 기간 ==========
        function duration = getDuration(obj)
            duration = obj.endTime_ms - obj.startTime_ms;
        end

        

        function overlap = getOverlapTime(obj, otherSignal)
            overlapStart = max(obj.startTime_ms, otherSignal.startTime_ms);
            overlapEnd = min(obj.endTime_ms, otherSignal.endTime_ms);
            overlap = max(0, overlapEnd - overlapStart);

        end
    end
end