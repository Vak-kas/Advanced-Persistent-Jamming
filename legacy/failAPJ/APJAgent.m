classdef APJAgent < Agent
    methods
        function obj = APJAgent(owner)
            env;
            obj@Agent(owner, numChannels);

            % ========== Replay Buffer ==========
            obj.ReplayBuffer = ReplayBuffer(apjReplayBufferCapacity);
            
            % ========== DQN Parameters ==========
            obj.BatchSize = apjBatchSize;

            obj.LearningRate = apjLearnRate;
            obj.DiscountFactor = apjDiscountFactor;

            % ========== Epsilon-Greedy ==========
            obj.Epsilon = apjEpsilon;
            obj.EpsilonMin = apjEpsilonMin;
            obj.EpsilonDecay = apjEpsilonDecay;

            % ========== Network ==========
            inputSize = size(owner.StateManager.getState());

            if numel(inputSize) == 2
                inputSize = [inputSize 1];
            end

            obj.QNetwork = obj.createQNetwork3(inputSize, numChannels, obj.NumActions);
            % obj.QNetwork = obj.createQNetwork1(inputSize, obj.NumActions);
            obj.TargetNetwork = obj.QNetwork;

            obj.TargetUpdateFrequency = apjTargetUpdateFrequency;

            % ========== Reward ==========
            obj.RewardFunction = apjRewardFunction;

        end
        %% ========== Target Beam의 실제 Action 관측 ==========
        function observeAction(obj, state, occupancy, observedAction)
            obj.setPendingState(state);
            obj.setPendingOccupancy(occupancy);
            obj.setPendingAction(observedAction);
        end



        %% ========== Target Beam Action 예측 ==========
        function [predictedAction, qValues] = predictAction(obj, state, occupancy)
            % State 입력
            dlState = obj.convertStateToDLArray(state);

            % Occupancy 입력
            dlOccupancy = obj.convertOccupancyToDLArray(occupancy);

            %  Q-value 계산
            dlQvalues = predict(obj.QNetwork, dlState, dlOccupancy);
            qValues = extractdata(dlQvalues);
            qValues = qValues(:);

            % Greedy Prediction
            [~, predictedAction] = max(qValues);
            predictedAction = double(predictedAction);

        end
    end


    methods (Access=private)
        function network = createQNetwork3(~, imageInputSize, numChannels, numActions)
            lgraph = layerGraph();
        
            % 1. 이미지(스펙트럼 워터폴) 브랜치 — feature까지만, fc2(액션 출력)는 제거
            imageLayers = [
                imageInputLayer(imageInputSize, Normalization="none", Name="spectrum_waterfall_input")
                convolution2dLayer([10 4], 16, Stride=2, Padding="same", Name="Convolution")
                reluLayer(Name="relu_conv")
                fullyConnectedLayer(128, Name="img_fc1")
                reluLayer(Name="img_relu1")
            ];
        
            % 2. 점유 벡터(occupancy) 브랜치
            occupancyLayers = [
                featureInputLayer(numChannels, Normalization="none", Name="occupancy_input")
                fullyConnectedLayer(32, Name="occ_fc")
                reluLayer(Name="occ_relu")
            ];
        
            % 3. 결합 후 Q-value
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
            lgraph = connectLayers(lgraph, "occ_relu",  "feature_concat/in2");
        
            network = dlnetwork(lgraph);
        end
        

    end
end