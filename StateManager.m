classdef StateManager < handle
    properties
        NumUpdates = 0

        NumChannels  % k
        HistoryLength % HistoryLength % Waterfall 길이(phi)
        Mode % Mode % O / OA / OAH


        CurrentObservation %o_t (1*k)

        ObservationHistory %(phi * k)
        ActionHistory %(phi * k)
        HarqHistory % (phi * k)

        CurrentOccupancy

    end


    methods
        % ========== 생성자 ==========
        function obj = StateManager(numChannels, historyLength, mode)
            obj.NumChannels = numChannels;
            obj.HistoryLength = historyLength;
            obj.Mode = mode;

            obj.CurrentObservation = zeros(1, obj.NumChannels);
            obj.ObservationHistory = zeros(obj.HistoryLength, obj.NumChannels);
            obj.ActionHistory = zeros(obj.HistoryLength, obj.NumChannels);
            obj.HarqHistory = zeros(obj.HistoryLength, obj.NumChannels);

            obj.CurrentOccupancy = zeros(1, obj.NumChannels);
        end

        % ========== 한 Slot의 O / A / H 업데이트 ==========
        function update(obj, observation, selectedChannel, packetType)
            obj.updateObservation(observation);
            obj.updateAction(selectedChannel);
            obj.updateHARQ(selectedChannel, packetType);

            obj.NumUpdates = obj.NumUpdates + 1;

        end


        % ========== Observation History 업데이트 ==========
        function updateObservation(obj, observation)
            observation = reshape(observation, 1, []);

            if numel(observation) ~= obj.NumChannels
                error("StateManager:InvalidObservationSize", "Observation size must be 1 x %d.", obj.NumChannels);
            end

            obj.ObservationHistory = [
                observation
                obj.ObservationHistory(1:end-1, :)
            ];

        end

        % ========== Action History 업데이트 ==========
        function updateAction(obj, selectedChannel)
            if selectedChannel < 1 || selectedChannel > obj.NumChannels
                error("StateManager:InvalidChannel", "Selected channel must be between 1 and %d.", obj.NumChannels);
            end

            actionVector = zeros(1, obj.NumChannels);
            actionVector(selectedChannel) = 1;

            obj.ActionHistory = [
                actionVector
                obj.ActionHistory(1:end-1, :)
            ];

        end

        % ========== HARQ History 업데이트 ==========
        function updateHARQ(obj, selectedChannel, packetType)
            harqVector = zeros(1, obj.NumChannels);

            if packetType == PacketType.ACK
                harqVector(selectedChannel) = 1;
            elseif packetType == PacketType.NACK
                harqVector(selectedChannel) = -1;
            else
                error("StateManager:InvalidHARQ", "Packet type must be ACK or NACK.");
            end

            obj.HarqHistory = [
                harqVector
                obj.HarqHistory(1:end-1, :)
            ];

        end

        % ========== Agent 입력 반환 ==========
        function state = getState(obj)

            % Observation 정규화
            normalizedObservation = obj.normalizeObservation(obj.ObservationHistory);

            switch obj.Mode
                case ObservationMode.O
                    state = normalizedObservation;

                case ObservationMode.OA
                    state = cat(3, ...
                        normalizedObservation, ...
                        obj.ActionHistory);

                case ObservationMode.OAH
                    state = cat(3, ...
                        normalizedObservation, ...
                        obj.ActionHistory, ...
                        obj.HarqHistory);

                otherwise
                    error("StateManager:InvalidMode", ...
                        "Unknown observation mode: %s", obj.Mode);
            end
        end

        % function state = getState(obj)
        %     switch obj.Mode
        %         case ObservationMode.O
        %             state = obj.ObservationHistory;
        %         case ObservationMode.OA
        %             state = cat(3, obj.ObservationHistory, obj.ActionHistory);
        %         case ObservationMode.OAH
        %             state = cat(3, obj.ObservationHistory, obj.ActionHistory, obj.HarqHistory);
        %         otherwise
        %                 error("ObservationManager:InvalidMode", "Unknown observation mode: %s", obj.Mode);
        %     end
        % end



        %% ========== History 준비 여부 ==========
        function ready = isReady(obj)
            ready = obj.NumUpdates >= obj.HistoryLength;
        end

        %% ========== State 초기화 ==========
        function reset(obj)
            obj.NumUpdates = 0;
            obj.ObservationHistory(:) = 0;
            obj.ActionHistory(:) = 0;
            obj.HarqHistory(:) = 0;
            obj.CurrentOccupancy(:) = 0;
        end


        function normalizedObservation = normalizeObservation(obj, observation)

            minPower_dBm = -120;
            maxPower_dBm = -90;
        
            normalizedObservation = ...
                (observation - minPower_dBm) ./ ...
                (maxPower_dBm - minPower_dBm);
        
            % 0 ~ 1 범위 제한
            normalizedObservation = max(0, min(1, normalizedObservation));
        
        end


        % ========== 신규: 이번 슬롯 실시간 점유 벡터 갱신 ==========
        function setCurrentOccupancy(obj, occupancyVector)
            occupancyVector = reshape(occupancyVector, 1, []);
            if numel(occupancyVector) ~= obj.NumChannels
                error("StateManager:InvalidOccupancySize", "Occupancy size must be 1 x %d.", obj.NumChannels);
            end
            obj.CurrentOccupancy = occupancyVector;
        end

        % ========== 신규: C만 별도로 꺼내는 접근자 ==========
        function occupancy = getCurrentOccupancy(obj)
            occupancy = obj.CurrentOccupancy;
        end

    end

    

end