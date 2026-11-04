classdef ReplayBuffer < handle
    properties
        Capacity
        Count
        Position
        States
        Occupancies         % 1 x numChannels 벡터 저장 (cell array)
        Actions
        Rewards
        NextStates
        NextOccupancies      % 1 x numChannels 벡터 저장 (cell array)
    end

    methods
        % ========== 생성자 ========== %
        function obj = ReplayBuffer(capacity)
            obj.Capacity = capacity;
            obj.Count = 0;
            obj.Position = 1;
            obj.States = cell(1, capacity);
            obj.Occupancies = cell(1, capacity);       % ← cell로 수정
            obj.Actions = zeros(1, capacity);
            obj.Rewards = zeros(1, capacity);
            obj.NextStates = cell(1, capacity);
            obj.NextOccupancies = cell(1, capacity);    % ← cell로 수정
        end

        % ========== Transition 저장 ==========
        function add(obj, state, occupancy, action, reward, nextState, nextOccupancy)
            bufferIndex = obj.Position;
            obj.States{bufferIndex} = state;
            obj.Occupancies{bufferIndex} = occupancy;
            obj.Actions(bufferIndex) = action;
            obj.Rewards(bufferIndex) = reward;
            obj.NextStates{bufferIndex} = nextState;
            obj.NextOccupancies{bufferIndex} = nextOccupancy;

            obj.Count = min(obj.Count + 1, obj.Capacity);
            obj.Position = mod(obj.Position, obj.Capacity) + 1;
        end

        % ========== Mini-Batch Sampling ==========
        function [states, occupancies, actions, rewards, nextStates, nextOccupancies] = sample(obj, batchSize)
            states = [];
            occupancies = [];
            actions = [];
            rewards = [];
            nextStates = [];
            nextOccupancies = [];

            % 저장된 Transition이 BatchSize보다 적으면 학습 불가능
            if obj.Count < batchSize
                return;
            end

            sampleIndices = randperm(obj.Count, batchSize); % 랜덤 샘플링

            % Mini-Batch
            states = obj.States(sampleIndices);
            occupancies = obj.Occupancies(sampleIndices);
            actions = obj.Actions(sampleIndices);
            rewards = obj.Rewards(sampleIndices);
            nextStates = obj.NextStates(sampleIndices);
            nextOccupancies = obj.NextOccupancies(sampleIndices);
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
            obj.Occupancies(:) = {[]};
            obj.Actions(:) = 0;
            obj.Rewards(:) = 0;
            obj.NextStates(:) = {[]};
            obj.NextOccupancies(:) = {[]};
        end
    end
end