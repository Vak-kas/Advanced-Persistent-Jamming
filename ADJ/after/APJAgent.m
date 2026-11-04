classdef APJAgent < Agent

    methods
        function obj = APJAgent(owner)
            env;

            obj@Agent(owner, numChannels);

            % Shadow DQN 전용 하이퍼파라미터 (Target Beam과 독립)
            obj.ReplayBuffer = ReplayBuffer(apjReplayBufferCapacity);
            obj.BatchSize = apjBatchSize;
            obj.LearningRate = apjLearnRate;
            obj.DiscountFactor = apjDiscountFactor;

            % Shadow는 자기 action을 epsilon-greedy로 선택하지 않음
            obj.Epsilon = apjEpsilon;
            obj.EpsilonMin = apjEpsilonMin;
            obj.EpsilonDecay = apjEpsilonDecay;

            inputSize = size(owner.StateManager.getState());
            if numel(inputSize) == 2
                inputSize = [inputSize 1];
            end

            obj.QNetwork = obj.createQNetwork3(inputSize, numChannels, obj.NumActions);
            obj.TargetNetwork = obj.QNetwork;
            obj.TargetUpdateFrequency = apjTargetUpdateFrequency;
            obj.RewardFunction = apjRewardFunction;
        end


        %% ========== Target Beam 실제 Action 관측 ==========
        function observeAction(obj, state, occupancy, observedAction)
            obj.setPendingState(state);
            obj.setPendingOccupancy(occupancy);
            obj.setPendingAction(observedAction);
        end


        %% ========== Shadow DQN 기반 Target Action 예측 ==========
        function [predictedAction, qValues] = predictAction(obj, state, occupancy)
            dlState = obj.convertStateToDLArray(state);
            dlOccupancy = obj.convertOccupancyToDLArray(occupancy);
            dlQValues = predict(obj.QNetwork, dlState, dlOccupancy);
            qValues = double(extractdata(dlQValues(:)));
            [~, predictedAction] = max(qValues);
            predictedAction = double(predictedAction);
        end
    end


    methods (Access = private)

        function network = createQNetwork3(~, imageInputSize, numChannels, numActions)
            lgraph = layerGraph();

            imageLayers = [
                imageInputLayer(imageInputSize, Normalization="none", Name="spectrum_waterfall_input")
                convolution2dLayer([10 4], 16, Stride=2, Padding="same", Name="Convolution")
                reluLayer(Name="relu_conv")
                fullyConnectedLayer(128, Name="img_fc1")
                reluLayer(Name="img_relu1")
            ];

            occupancyLayers = [
                featureInputLayer(numChannels, Normalization="none", Name="occupancy_input")
                fullyConnectedLayer(32, Name="occ_fc")
                reluLayer(Name="occ_relu")
            ];

            headLayers = [
                concatenationLayer(1, 2, Name="feature_concat")
                fullyConnectedLayer(128, Name="head_fc1")
                reluLayer(Name="head_relu")
                fullyConnectedLayer(numActions, Name="q_values")
            ];

            lgraph = addLayers(lgraph, imageLayers);
            lgraph = addLayers(lgraph, occupancyLayers);
            lgraph = addLayers(lgraph, headLayers);
            lgraph = connectLayers(lgraph, "img_relu1", "feature_concat/in1");
            lgraph = connectLayers(lgraph, "occ_relu", "feature_concat/in2");

            network = dlnetwork(lgraph);
        end

    end
end