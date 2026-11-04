classdef IntelligentJammerAgent < Agent
    properties
        ActionTable   % numActions x jammingBudget, action index -> 채널 조합
    end

    methods
        %% ========== 생성자 ==========
        function obj = IntelligentJammerAgent(owner)
            env;

            numActions = nchoosek(numChannels, ijJammingBudget);
            obj@Agent(owner, numActions);

            obj.ActionTable = nchoosek(1:numChannels, ijJammingBudget);

            obj.ReplayBuffer = ReplayBuffer(ijReplayBufferCapacity);
            obj.BatchSize      = ijBatchSize;
            obj.LearningRate   = ijLearnRate;
            obj.DiscountFactor = ijDiscountFactor;

            obj.Epsilon      = ijEpsilon;
            obj.EpsilonMin   = ijEpsilonMin;
            obj.EpsilonDecay = ijEpsilonDecay;

            % [수정] 입력 크기를 owner.StateManager의 state 크기에서 가져옴
            % (IntelligentJammer의 StateManager phi 설정과 자동으로 일치)
            inputSize = size(owner.StateManager.getState());
            if numel(inputSize) == 2
                inputSize = [inputSize 1];
            end

            obj.QNetwork = obj.createQNetwork(inputSize, numChannels, obj.NumActions);
            obj.TargetNetwork = obj.QNetwork;
            obj.TargetUpdateFrequency = ijTargetUpdateFrequency;

            % Eq.(24): reward = 재밍한 채널들의 감지 에너지 (연속값, ACK/NACK 아님)
            % obj.RewardFunction = @(sensedPower) sensedPower;
            obj.RewardFunction = ijRewardFunction;
        end

        %% ========== Epsilon-Greedy Action 선택 ==========
        function [actionIndex, method, randomValue, qValues] = selectAction(obj, state, occupancy)
            randomValue = rand();

            if randomValue < obj.Epsilon
                actionIndex = randi(obj.NumActions);
                method = "random";
                qValues = [];
            else
                dlState = obj.convertStateToDLArray(state);
                dlOccupancy = obj.convertOccupancyToDLArray(occupancy);
                dlQValues = predict(obj.QNetwork, dlState, dlOccupancy);
                qValues = double(extractdata(dlQValues(:)));
                [~, actionIndex] = max(qValues);
                method = "greedy";
            end

            obj.setPendingState(state);
            obj.setPendingOccupancy(occupancy);
            obj.setPendingAction(actionIndex);

            obj.Epsilon = max(obj.EpsilonMin, obj.Epsilon * obj.EpsilonDecay);
        end

        %% ========== Action Index -> 채널 조합 디코딩 ==========
        function channels = decodeAction(obj, actionIndex)
            channels = obj.ActionTable(actionIndex, :);
        end
    end

    methods (Access = private)
        %% ========== FCNN 기반 Q-Network (Jing et al. 스타일, conv 없음) ==========
        function network = createQNetwork(~, imageInputSize, numOccupancyChannels, numActions)
            lgraph = layerGraph();

            stateLayers = [
                imageInputLayer(imageInputSize, Normalization="none", Name="state_input")
                flattenLayer(Name="state_flatten")
                fullyConnectedLayer(64, Name="state_fc1")
                reluLayer(Name="state_relu1")
                fullyConnectedLayer(64, Name="state_fc2")
                reluLayer(Name="state_relu2")
            ];

            occupancyLayers = [
                featureInputLayer(numOccupancyChannels, Normalization="none", Name="occupancy_input")
                fullyConnectedLayer(8, Name="occ_fc")
                reluLayer(Name="occ_relu")
            ];

            headLayers = [
                concatenationLayer(1, 2, Name="feature_concat")
                fullyConnectedLayer(64, Name="head_fc1")
                reluLayer(Name="head_relu")
                fullyConnectedLayer(numActions, Name="q_values")
            ];

            lgraph = addLayers(lgraph, stateLayers);
            lgraph = addLayers(lgraph, occupancyLayers);
            lgraph = addLayers(lgraph, headLayers);
            lgraph = connectLayers(lgraph, "state_relu2", "feature_concat/in1");
            lgraph = connectLayers(lgraph, "occ_relu", "feature_concat/in2");

            network = dlnetwork(lgraph);
        end
    end
end