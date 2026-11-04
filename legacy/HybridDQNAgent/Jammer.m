classdef Jammer < Node

    properties
        currentChannels
        Tj_ms
        jamType
    end

    methods

        %========== 생성자 ==========
        function obj = Jammer(id, FHP, position, txPower, type, Tc_ms, Tj_ms)

            obj@Node( ...
                id, ...
                NodeType.Jammer, ...
                position, ...
                txPower, ...
                FHP, ...
                Tc_ms ...
            );

            obj.jamType = type;
            obj.Tj_ms = Tj_ms;
            obj.currentChannels = {};

        end


        %========== Jammer 채널 선택 ==========
        function ch = selectChannel(obj, slot, channels)

            K = length(channels);

            channelIds = obj.FHP( ...
                slot, ...
                K, ...
                obj.Tc_ms, ...
                obj.Tj_ms ...
            );

            if isempty(channelIds)

                obj.currentChannels = {};
                ch = obj.currentChannels;
                return;

            end

            if iscell(channelIds)
                channelIds = cell2mat(channelIds);
            end

            channelIds = channelIds(:).';

            channelIds = unique(channelIds,'stable');

            channelIds = channelIds( ...
                channelIds >= 1 & ...
                channelIds <= K ...
            );

            obj.currentChannels = cell(1,length(channelIds));

            for i = 1:length(channelIds)

                obj.currentChannels{i} = ...
                    channels{channelIds(i)};

            end

            ch = obj.currentChannels;

        end


        %========== 재밍 ==========
        function jam(obj, slot)
        
            switch obj.jamType
                case "comb"
                    obj.combJam(slot);
        
                case "swept"
                    obj.sweptJam(slot);
        
                otherwise
                    error("Unknown jammer type");
            end
        end


        %========== Comb ==========
        function combJam(obj, slot)
        
            relStart_ms = 0;
            relEnd_ms   = obj.Tc_ms;
        
            for i = 1:length(obj.currentChannels)
        
                channel = obj.currentChannels{i};
        
                sig = Signal( ...
                    SignalType.JAMMING, ...
                    [], ...
                    obj.txPower, ...
                    obj.id, ...
                    obj.role, ...
                    channel.id, ...
                    obj.position, ...
                    relStart_ms, ...
                    relEnd_ms ...
                );
        
                channel.addSignal(sig);
        
            end
        
        end


        %========== Swept ==========
        function sweptJam(obj, slot)
        
            if isempty(obj.currentChannels)
                return;
            end
        
            slotStartAbs_ms = (slot - 1) * obj.Tc_ms;
            slotEndAbs_ms   = slot * obj.Tc_ms;
        
            abs_t = slotStartAbs_ms;
            idx = 1;
        
            while abs_t < slotEndAbs_ms && idx <= length(obj.currentChannels)
        
                jamIndex = floor(abs_t / obj.Tj_ms);
                nextSwitchAbs_ms = (jamIndex + 1) * obj.Tj_ms;
                segmentEndAbs_ms = min(slotEndAbs_ms, nextSwitchAbs_ms);
        
                relStart_ms = abs_t - slotStartAbs_ms;
                relEnd_ms   = segmentEndAbs_ms - slotStartAbs_ms;
        
                channel = obj.currentChannels{idx};
        
                sig = Signal( ...
                    SignalType.JAMMING, ...
                    [], ...
                    obj.txPower, ...
                    obj.id, ...
                    obj.role, ...
                    channel.id, ...
                    obj.position, ...
                    relStart_ms, ...
                    relEnd_ms ...
                );
        
                channel.addSignal(sig);
        
                abs_t = segmentEndAbs_ms;
                idx = idx + 1;
            end
        end


    end

end