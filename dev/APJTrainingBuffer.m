classdef APJTrainingBuffer < handle
    properties
        Capacity
        Count
        Position

        States    % StateManager.getState() 그대로 (OAH 텐서, a_t/r_t 이미 포함) — cell array
        Labels     % a_{t+1} (다음 슬롯 실제 채널) — 정수 배열
    end

    methods
        % ========== 생성자 ==========
        function obj = APJTrainingBuffer(capacity)
            obj.Capacity = capacity;
            obj.Count = 0;
            obj.Position = 1;

            obj.States = cell(1, capacity);
            obj.Labels = zeros(1, capacity);
        end

        % ========== (state, label) 저장 ==========
        function add(obj, state, label)
            bufferIndex = obj.Position;

            obj.States{bufferIndex} = state;
            obj.Labels(bufferIndex) = label;

            obj.Count = min(obj.Count + 1, obj.Capacity);
            obj.Position = mod(obj.Position, obj.Capacity) + 1;
        end

        % ========== Mini-Batch Sampling ==========
        function [states, labels] = sample(obj, batchSize)
            states = [];
            labels = [];

            if obj.Count < batchSize
                return;
            end

            sampleIndices = randperm(obj.Count, batchSize);
            states = obj.States(sampleIndices);
            labels = obj.Labels(sampleIndices);
        end

        % ========== 학습 가능 여부 ==========
        function ready = isReady(obj, batchSize)
            ready = obj.Count >= batchSize;
        end

        % ========== 현재 Buffer 크기 반환 ==========
        function count = getCount(obj)
            count = obj.Count;
        end

        % ========== Buffer 초기화 ==========
        function reset(obj)
            obj.Count = 0;
            obj.Position = 1;
            obj.States(:) = {[]};
            obj.Labels(:) = 0;
        end
    end
end