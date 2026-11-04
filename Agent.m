classdef (Abstract) Agent < handle
    properties

        % ========== 기본 정보 ==========
        Owner
        NumActions

        % ========== State / Pending Transition ==========
        CurrentState        % S_{t+1}
        PendingState        % S_t
        PendingAction       % a_t
        PendingReward       % r_t

        PendingOccupancy
        CurrentOccupancy

        % ========== Training ==========
        TrainingStep

        AverageGradients
        AverageSquaredGradients

        % ========== Training Statistics ==========
        RewardHistory
        OutcomeHistory




        % ========== Replay Buffer ==========
        ReplayBuffer

        % ========== DQN Parameters ==========
        BatchSize

        LearningRate
        DiscountFactor

        % ========== Epsilon-Greedy ==========
        Epsilon
        EpsilonMin
        EpsilonDecay

        % ========== Network ==========
        QNetwork
        TargetNetwork

        TargetUpdateFrequency


        % ========== Reward ==========
        RewardFunction

    end

    
    methods
        % ========== 생성자 ==========
        function obj = Agent(owner, numActions)
            % 기본 정보
            obj.Owner = owner;
            obj.NumActions = numActions;

            % State/ Pending Transition
            obj.CurrentState = [];
            
            obj.PendingState = [];
            obj.PendingAction = [];
            obj.PendingReward = [];

            obj.PendingOccupancy = [];
            obj.CurrentOccupancy = [];

            % Training
            obj.TrainingStep = 0;

            obj.RewardHistory = [];
            obj.OutcomeHistory = [];
            
            obj.AverageGradients = [];
            obj.AverageSquaredGradients = [];

        end

        % ========== 현재 State 등록 ==========
        function setCurrentState(obj, state)
            obj.CurrentState = state;
        end
        
        
        % ========== Pending State 등록 ==========
        function setPendingState(obj, state)
            obj.PendingState = state;
        end
        
        
        % ========== Pending Action 등록 ==========
        function setPendingAction(obj, action)
            obj.PendingAction = action;
        end
        
        
        % ========== 보상 등록 ========== %
        function setReward(obj, outcome)

            if isempty(obj.RewardFunction)
                error("Agent:RewardFunctionNotSet", "RewardFunction이 등록되지 않았습니다.");
            end

            
            % Reward 계산
            reward = obj.RewardFunction(outcome);
            obj.PendingReward = reward;
            obj.OutcomeHistory(end + 1) = double(outcome);
            obj.RewardHistory(end + 1) = reward;
        end
        
        % ========== Pending Occupancy 등록 ==========
        function setPendingOccupancy(obj, occupancy)
            obj.PendingOccupancy = occupancy;
        end

        % ========== Current Occupancy 등록 ==========
        function setCurrentOccupancy(obj, occupancy)
            obj.CurrentOccupancy = occupancy;
        end

        % ========== Transition 완성 및 Replay Buffer 저장 ========== %
        function completeTransition(obj)
            if isempty(obj.PendingState) || isempty(obj.PendingAction) || isempty(obj.PendingReward) || isempty(obj.CurrentState)
                return;
            end
            if isempty(obj.ReplayBuffer)
                error("Agent:ReplayBufferNotSet", "ReplayBuffer가 설정되지 않았습니다.");
            end
        
            % occupancy도 같이 저장
            obj.ReplayBuffer.add(obj.PendingState, obj.PendingOccupancy, obj.PendingAction, obj.PendingReward, obj.CurrentState, obj.CurrentOccupancy);
        
            obj.PendingState = [];
            obj.PendingOccupancy = [];
            obj.PendingAction = [];
            obj.PendingReward = [];
        end


        % ========== State를 DQN 입력으로 변환 ==========
        function dlState = convertStateToDLArray(obj, state)
        
            % O Mode: phi x K
            if ndims(state) == 2
                state = reshape(state, size(state, 1), size(state, 2), 1, 1);
            else
                % OA / OAH: phi x K x C
                state = reshape(state, size(state, 1), size(state, 2), size(state, 3), 1);
            end
        
            dlState = dlarray(single(state), "SSCB");
        
        end

        % ========== Occupancy를 DQN 입력으로 변환 ==========
        function dlOccupancy = convertOccupancyToDLArray(obj, occupancy)
            occupancy = reshape(occupancy, [], 1);   % numChannels x 1
            dlOccupancy = dlarray(single(occupancy), "CB");
        end

        % ========== DQN 학습 ==========
        function [lossValue, trainingInfo] = train(obj)
            lossValue = [];
            trainingInfo = struct("MeanQValue", [], "MaxQValue", [], "MeanTargetQValue", []);

            % Replay Buffer 확인
            if isempty(obj.ReplayBuffer)
                error( "Agent:ReplayBufferNotSet", "ReplayBuffer가 설정되지 않았습니다.");
            end

            % Replay Buffer가 충분히 쌓이지 않았으면 학습하지 않음
            if ~obj.ReplayBuffer.isReady(obj.BatchSize)
                return;
            end

            % 1. Batch 추출 (occupancy 포함, 6개)
            [states, occupancies, actions, rewards, nextStates, nextOccupancies] = obj.ReplayBuffer.sample(obj.BatchSize);

            % 2. Deep Learning 입력 방식으로 변환
            stateBatch = obj.stackStates(states);
            nextStateBatch = obj.stackStates(nextStates);
            occupancyBatch = obj.stackOccupancies(occupancies);
            nextOccupancyBatch = obj.stackOccupancies(nextOccupancies);

            dlStates = dlarray(single(stateBatch), "SSCB");
            dlNextStates = dlarray(single(nextStateBatch), "SSCB" );
            dlOccupancies = dlarray(single(occupancyBatch), "CB");
            dlNextOccupancies = dlarray(single(nextOccupancyBatch), "CB");
            dlRewards = dlarray(reshape(single(rewards), 1, obj.BatchSize), "CB");



            % 3. Target Q-Value 계산 (TargetNetwork 추론 -> max Next Q 추출 -> % Target 계산)
            dlTargetQValues = obj.calculateTargetQValues(dlNextStates, dlNextOccupancies, dlRewards);

            % 4. Loss / Gradient 계산
            [loss, gradients, dlSelectedQValues] = dlfeval(@(qNetwork, inputStates, inputOccupancies, inputActions, targetQValues) obj.modelGradients( ...
                    qNetwork, inputStates, inputOccupancies, inputActions, targetQValues), obj.QNetwork, dlStates, dlOccupancies, actions, dlTargetQValues);

            % 5. Q-Network Weight Update

            obj.TrainingStep = obj.TrainingStep + 1;
           [obj.QNetwork, obj.AverageGradients, obj.AverageSquaredGradients] = adamupdate( ...
                obj.QNetwork, gradients, obj.AverageGradients, obj.AverageSquaredGradients, obj.TrainingStep, obj.LearningRate);

           % 6. Target Network Update
            if mod(obj.TrainingStep, obj.TargetUpdateFrequency) == 0
                obj.TargetNetwork = obj.QNetwork;
            end

            % 7. Loss 반환
            lossValue = double(extractdata(loss));
            selectedQValues = extractdata(dlSelectedQValues);
            targetQValues = extractdata(dlTargetQValues);
            trainingInfo.MeanQValue = mean(selectedQValues, "all");
            trainingInfo.MaxQValue = max(selectedQValues, [], "all");
            trainingInfo.MeanTargetQValue = mean(targetQValues, "all");

        end


        % ========== State Cell을 Batch Tensor로 변환 ==========
        function stateBatch = stackStates(obj, states)
            batchSize = numel(states);
            sampleState = states{1};
        
            % O Mode: phi x K -> phi x K x 1
            if ndims(sampleState) == 2
                sampleState = reshape(sampleState, size(sampleState, 1), size(sampleState, 2), 1);
            end
        
            stateHeight = size(sampleState, 1);
            stateWidth = size(sampleState, 2);
            stateChannels = size(sampleState, 3);
            stateBatch = zeros(stateHeight, stateWidth, stateChannels, batchSize,  "single");
        
            for batchIndex = 1:batchSize
                state = states{batchIndex};

                % O Mode
                if ndims(state) == 2
                    state = reshape(state, size(state, 1), size(state, 2), 1);
                end
                stateBatch(:, :, :, batchIndex) = single(state);
            end
        end

        % ========== Occupancy Cell을 Batch Tensor로 변환 ==========
        function occupancyBatch = stackOccupancies(obj, occupancies)
            batchSize = numel(occupancies);
            sampleOccupancy = reshape(occupancies{1}, [], 1);   % numChannels x 1

            numChannels = numel(sampleOccupancy);
            occupancyBatch = zeros(numChannels, batchSize, "single");

            for batchIndex = 1:batchSize
                occupancyBatch(:, batchIndex) = single(reshape(occupancies{batchIndex}, [], 1));
            end
        end


        % ========== Target Q-Value 계산 ========== %
        function dlTargetQValues = calculateTargetQValues(obj, dlNextStates, dlNextOccupancies, dlRewards)
            % O_{t+1}에서 각 행동의 Q-value 계산
            dlNextQValues = predict(obj.TargetNetwork, dlNextStates, dlNextOccupancies);
            dlMaxNextQValues = max(dlNextQValues, [], 1);

            % Bellman Target ->  y_t = r_t + gamma × max_a Q_target(O_{t+1}, a)
                % 현재 행동의 가치 = 이번 행동으로 즉시 받은 보상 + 다음 상태에서 가장 좋아보이는 행동의 미래 가치
            dlTargetQValues = dlRewards + single(obj.DiscountFactor) .* dlMaxNextQValues;
        end


        % ========== Current Q / Loss / Gradient 계산 ==========
        function [loss, gradients, dlSelectedQValues] = modelGradients(obj, qNetwork, dlStates, dlOccupancies, actions, dlTargetQValues)
        
            % 모든 Action의 Q-value
            dlCurrentQValues = forward(qNetwork, dlStates, dlOccupancies);
        
            batchSize = numel(actions);
        
            % 실제 수행했던 Action의 Q-value 추출
            actions = double(actions(:))';
        
            actionIndices = sub2ind([obj.NumActions, batchSize], actions, 1:batchSize );
        
            dlSelectedQValues = dlCurrentQValues(actionIndices);
            dlSelectedQValues = reshape(dlSelectedQValues, 1, batchSize);
        
            % Loss
            loss = mean((dlSelectedQValues - dlTargetQValues).^2, "all" );
        
            % Gradient
            gradients = dlgradient(loss, qNetwork.Learnables);
        end


        
    end
end