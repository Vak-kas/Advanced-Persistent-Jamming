classdef Channel < handle
    properties
        id
        centerFreq
        bandwidth

        signals
    end

    methods
        %========== 채널 생성자 ==========
        function obj = Channel(id, centerFreq, bandwidth)
            obj.id = id;
            obj.centerFreq = centerFreq;
            obj.bandwidth = bandwidth;
            obj.signals = {};
        end

        %========== 채널 상태 초기화 ==========
        function reset(obj)
            obj.signals = {};
        end

        %========== Signal 추가 ==========
        function addSignal(obj, signal)
            obj.signals{end+1} = signal;
        end

        %========== Signal 가져오기 ==========
        function signals = getSignals(obj)
            signals = obj.signals;
        end


        %========== Channel의 시그널 상태 확인하기 ==========
        function printSignals(obj)
            fprintf("\n[Channel %d] Signal Count = %d\n", obj.id, length(obj.signals));

            if isempty(obj.signals)
                fprintf("  Empty\n");
                return;
            end
        
            for i = 1:length(obj.signals)
                sig = obj.signals{i};
                fprintf("  Signal %d | Type=%s | TxNode=%d | Power=%.2f",i, string(sig.type), sig.txNodeId, sig.txPower);
        
                if ~isempty(sig.packet)
                    fprintf(" | Packet=%s | Src=%d -> Dst=%d", string(sig.packet.type), sig.packet.srcId, sig.packet.dstId);
                end
        
                fprintf("\n");
            end
        end

        function removeCommSignals(obj)
            newSignals = {};
        
            for i = 1:length(obj.signals)
                sig = obj.signals{i};
        
                if sig.type == SignalType.JAMMING
                    newSignals{end+1} = sig;
                end
            end

            obj.signals = newSignals;
        end
        


    end

end