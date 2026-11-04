classdef BeamAgent < Agent
    methods
        function obj = BeamAgent(owner)
            env;

            obj@Agent(owner, numChannels);

            % ========== Replay Buffer ==========
            obj.ReplayBuffer = ReplayBuffer(beamReplayBufferCapacity);
            
            % ========== DQN Parameters ==========
            obj.BatchSize = beamBatchSize;

            obj.LearningRate = beamLearnRate;
            obj.DiscountFactor = beamDiscountFactor;

            % ========== Epsilon-Greedy ==========
            obj.Epsilon = beamEpsilon;
            obj.EpsilonMin = beamEpsilonMin;
            obj.EpsilonDecay = beamEpsilonDecay;

            % ========== Network ==========
            inputSize = size(owner.StateManager.getState());

            if numel(inputSize) == 2
                inputSize = [inputSize 1];
            end

            obj.QNetwork = obj.createQNetwork3(inputSize, numChannels, obj.NumActions);
            % obj.QNetwork = obj.createQNetwork1(inputSize, obj.NumActions);
            obj.TargetNetwork = obj.QNetwork;

            obj.TargetUpdateFrequency = beamTargetUpdateFrequency;

            % ========== Reward ==========
            obj.RewardFunction = beamRewardFunction;

        end


        % ========== Action 선택 ==========
    %     function [selectedAction, selectionMethod, randomValue, qValues] = selectAction(obj, state)
    % 
    %         obj.setPendingState(state);
    % 
    %         % Epsilon-Greedy
    %         randomValue = rand;
    %         qValues = [];
    % 
    %         if randomValue < obj.Epsilon
    %             selectionMethod = "Random";
    %             selectedAction = randi(obj.NumActions);
    % 
    %         else
    %             selectionMethod = "DQN";
    % 
    %             % State -> DQN 입력 변환
    %             dlState = obj.convertStateToDLArray(state);
    % 
    %             % Q-Value 계산
    %             dlQValues = predict(obj.QNetwork, dlState);
    %             qValues = extractdata(dlQValues);
    % 
    %             % 최대 Q-Value Action 선택
    %             [~, selectedAction] = max(qValues, [], 1);
    % 
    %             selectedAction = double(selectedAction);
    % 
    %         end
    % 
    %         obj.setPendingAction(selectedAction); % 선택 Action 저장
    % 
    % 
    %         % Epsilon Update
    %         obj.Epsilon = max(obj.EpsilonMin, obj.Epsilon * obj.EpsilonDecay);
    % 
    %     end
    % 

        function [selectedAction, selectionMethod, randomValue, qValues] = selectAction(obj, state, occupancy)
            obj.setPendingState(state);
            obj.setPendingOccupancy(occupancy);   % Agent에도 occupancy를 pending으로 저장해야 함 (아래 5번 참고)
        
            randomValue = rand;
            qValues = [];
        
            if randomValue < obj.Epsilon
                selectionMethod = "Random";
                selectedAction = randi(obj.NumActions);
            else
                selectionMethod = "DQN";
                dlState = obj.convertStateToDLArray(state);
                dlOccupancy = dlarray(single(reshape(occupancy, [], 1)), "CB");
        
                dlQValues = predict(obj.QNetwork, dlState, dlOccupancy);   % ← 2-input predict
                qValues = extractdata(dlQValues);
        
                [~, selectedAction] = max(qValues, [], 1);
                selectedAction = double(selectedAction);
            end
        
            obj.setPendingAction(selectedAction);
            obj.Epsilon = max(obj.EpsilonMin, obj.Epsilon * obj.EpsilonDecay);
        end
    end


    methods (Access = private)
        function network = createQNetwork(~, inputSize, numActions)
            layers = [
                imageInputLayer(inputSize, Normalization="none", Name="spectrum_waterfall_input")

                convolution2dLayer([3 3], 16, Padding="same", Name="conv1") 
                reluLayer(name="relu1")

                convolution2dLayer([3 3], 32, Padding="same", Name="conv2")
                reluLayer(Name="relu2")

                fullyConnectedLayer(128, Name="fc1")
                reluLayer(Name="relu3")

                fullyConnectedLayer(numActions, Name="q_values")
                ];

            network = dlnetwork(layers);
        end

        % 
        function network = createQNetwork1(~, inputSize, numActions)
            layers = [
                imageInputLayer(inputSize, Normalization="none", Name="spectrum_waterfall_input")

                convolution2dLayer([10 4], 16, Stride=2, Padding="same", Name="Convolution")
                reluLayer(Name="relu_conv")

                fullyConnectedLayer(128, Name="fc1")
                reluLayer(Name="relu_fc1")

                fullyConnectedLayer(numActions, Name="fc2")
            ];

            lgraph = layerGraph(layers);
            network = dlnetwork(lgraph);
        end
        

        function network = createQNetwork2(~, imageInputSize, numChannels, numActions)
            lgraph = layerGraph();
    
            % 1. 기존 OAH 이미지 브랜치
            imageLayers = [
                imageInputLayer(imageInputSize, Normalization="none", Name="oah_input")
                convolution2dLayer([3 3], 16, Padding="same", Name="conv1")
                reluLayer(Name="relu1")
                convolution2dLayer([3 3], 32, Padding="same", Name="conv2")
                reluLayer(Name="relu2")
                fullyConnectedLayer(128, Name="oah_feature")
                reluLayer(Name="oah_relu")
            ];
    
            % 2. 신규 C 브랜치 (실시간 점유 벡터)
            occupancyLayers = [
                featureInputLayer(numChannels, Normalization="none", Name="occupancy_input")
                fullyConnectedLayer(32, Name="occ_fc")
                reluLayer(Name="occ_relu")
            ];
    
            % 3. 결합 후 Q-value
            headLayers = [
                concatenationLayer(1, 2, Name="feature_concat")
                fullyConnectedLayer(128, Name="fc1")
                reluLayer(Name="relu3")
                fullyConnectedLayer(numActions, Name="q_values")
            ];
    
            lgraph = addLayers(lgraph, imageLayers);
            lgraph = addLayers(lgraph, occupancyLayers);
            lgraph = addLayers(lgraph, headLayers);
    
            lgraph = connectLayers(lgraph, "oah_relu", "feature_concat/in1");
            lgraph = connectLayers(lgraph, "occ_relu", "feature_concat/in2");
    
            network = dlnetwork(lgraph);
        end

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