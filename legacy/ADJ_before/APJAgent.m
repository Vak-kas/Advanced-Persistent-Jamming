classdef APJAgent < Agent
    properties
    end

    methods
        % ========== 생성자 ========== %
        function obj = APJAgent(owner)
            env;
            obj@Agent(owner);

            obj.BatchSize = apjBatchSize;

            obj.LearningRate = apjLearnRate;
            obj.DiscountFactor = apjDiscountFactor;

            obj.Epsilon = apjEpsilon;
            obj.EpsilonMin = apjEpsilonMin;
            obj.EpsilonDecay = apjEpsilonDecay;

            inputSize = [phi, K, 1];
            stateSize = [phi, K];

            obj.NumActions = K;

            obj.QNetwork = obj.createQNetwork(inputSize, obj.NumActions);
            obj.TargetNetwork = obj.QNetwork;

            obj.TargetUpdateFrequency = apjTargetUpdateFrequency;

            obj.RewardFunction = apjRewardFunction;

            obj.ReplayBuffer = ReplayBuffer(apjReplayBufferCapacity, stateSize);
        end

        % ========== Target UT의 관측 Action 등록 ========== %
        function setObservedAction(obj, observedChannel)
            % 관측 채널 유효성 검사
            if isempty(observedChannel)
                error("APJAgent:EmptyObservedAction", "Target UT의 관측 채널이 비어 있습니다.");
            end

            obj.PendingState = obj.CurrentState;
            obj.PendingAction = observedChannel;
        end

        % ========== Target UT 채널 예측 ========== %
        function [predictedChannel, qValues] = predictAction(obj)
            if isempty(obj.CurrentState)
                error("APJAgent:EmptyCurrentState", "예측 전에 CurrentState를 설정해야 합니다.");
            end

            %O_t : phi * K
            state = single(obj.CurrentState);
            state = reshape(state, size(state, 1), size(state, 2), 1, 1);

            dlState = dlarray(state, "SSCB");

            % Shadow DQN Q-value
            dlQValues = predict(obj.QNetwork, dlState);

            qValues = extractdata(dlQValues);
            qValues = double(qValues(:));

            % Greedy prediction
            [~, predictedChannel] = max(qValues);
            predictedChannel = double(predictedChannel);
        end


    end

    methods (Access = private)
        function network = createQNetwork(~, inputSize, numActions)
            layers = [
                imageInputLayer(inputSize, Normalization="none", Name="spectrum_waterfall_input")
                
                convolution2dLayer([3 3], 16, Padding="same", Name="conv1") %특정 채널 하나에 최근 3개의 시간 타임라인
                reluLayer(name="relu1")

                convolution2dLayer([3 3], 32, Padding="same", Name="conv2")
                reluLayer(Name="relu2")
                
                fullyConnectedLayer(128, Name="fc1")
                reluLayer(Name="relu3")

                fullyConnectedLayer(numActions, Name="q_values")
                ];

            network = dlnetwork(layers);
        end
    end
end