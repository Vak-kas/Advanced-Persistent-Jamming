classdef UTAgent < Agent
    properties
    end

    methods
        % ========== 생성자 ========== %
        function obj = UTAgent(owner)
            env;
            obj@Agent(owner);

            obj.BatchSize = utBatchSize;

            obj.LearningRate = utLearnRate;
            obj.DiscountFactor = utDiscountFactor;

            obj.Epsilon = utEpsilon;
            obj.EpsilonMin = utEpsilonMin;
            obj.EpsilonDecay = utEpsilonDecay;

            inputSize = [phi, K, 1];
            stateSize = [phi, K];

            obj.NumActions = K;

            obj.QNetwork = obj.createQNetwork(inputSize, obj.NumActions);
            obj.TargetNetwork = obj.QNetwork;

            obj.TargetUpdateFrequency = utTargetUpdateFrequency;

            obj.RewardFunction = utRewardFunction;

            obj.ReplayBuffer = ReplayBuffer(utReplayBufferCapacity, stateSize);

        end

    end
    methods
        % ========== 채널 선택 ========== %
        function action = selectAction(obj, debug)
            % debug 인자를 생략하면 false
            if nargin < 2
                debug = false;
            end


            if isempty(obj.CurrentState)
                error("UTAgent:EmptyCurrentState", "행동 선택 전에 CurrentState를 설정해야 합니다.");
            end

            % 선택 당시 Epsilon과 난수
            randomValue = rand;
            qValues = [];


            % Epsilon 적용
            if randomValue < obj.Epsilon
                % 랜덤 선택
                selectionMethod = "Random";
                action = randi(obj.NumActions);
                
            else
                % Q-vale에 따른 Action 선택
                selectionMethod = "DQN";

                % phi × K -> phi × K × 1 × 1
                state = single(obj.CurrentState);
                state = reshape(state, size(state, 1), size(state, 2), 1);

                % CNN 입력 차원 결정
                dlState = dlarray(state, "SSCB");

                % Q-value 추론
                dlQValues = predict(obj.QNetwork, dlState);
                qValues = extractdata(dlQValues);
                qValues = double(qValues(:)); %K x 1 배열로 재정리

                % 가장 큰 Q-value의 채널 선택
                [~, action] = max(qValues);
                action = double(action);

            end

            if debug
                DebugHelper.printUTActionSelection(obj.Owner.Id, selectionMethod, obj.Epsilon, randomValue, action, qValues);
            end

            % Epsilon Update
            obj.Epsilon = max(obj.EpsilonMin, obj.Epsilon * obj.EpsilonDecay); % Update epsilon

            % 현재 Transition의 상태와 행동 임시 저장
            obj.PendingState = obj.CurrentState;
            obj.PendingAction = action;
        end


        % ========== 현재 DQN의 Greedy Action 반환 ========== %
        function [greedyChannel, qValues] = getGreedyAction(obj)
            if isempty(obj.CurrentState)
                error("UTAgent:EmptyCurrentState", "Greedy Action 계산 전에 CurrentState를 설정해야 합니다.");
            end
        
            state = single(obj.CurrentState);
            state = reshape(state, size(state, 1), size(state, 2), 1, 1);
        
            dlState = dlarray(state, "SSCB");
            dlQValues = predict(obj.QNetwork, dlState);
            qValues = extractdata(dlQValues);
            qValues = double(qValues(:));
        
            [~, greedyChannel] = max(qValues);
            greedyChannel = double(greedyChannel);
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