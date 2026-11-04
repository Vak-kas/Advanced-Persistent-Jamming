classdef (Abstract) Agent < handle
    properties

        %% 초기 선언
        % Owner
        Owner

        NumActions

        TrainingStep % Agent가 지금까지 몇 번 학습 수행했는지


        % State (DQN Input)
        CurrentState % O_t+1(phi × K)

        % Pending Transition
        PendingState  %O_t
        PendingAction %a_t
        PendingReward %r_t

        % Adam Optimizer 상태
        AverageGradients
        AverageSquaredGradients


        %% APJ / UT에 따른 각각 선언
        BatchSize

        % Learning parameters
        LearningRate %학습 가중치
        DiscountFactor %미래 보상 정책

        % Epsilon-greedy
        Epsilon
        EpsilonMin
        EpsilonDecay

        % DQN
        QNetwork
        TargetNetwork

        TargetUpdateFrequency %Target QNet 업데이트 주기

        RewardFunction


        % Replay Memory
        ReplayBuffer

    end

    methods
        % ========== 생성자 ========== %
        function obj = Agent(owner)
            obj.Owner = owner;

            % State
            obj.CurrentState = [];
        
            % Pending Transition
            obj.PendingState = [];
            obj.PendingAction = [];
            obj.PendingReward = [];
        
            % Training
            obj.TrainingStep = 0;

            obj.AverageGradients = [];
            obj.AverageSquaredGradients = [];

        end


        % ========== 상태 등록 ========== %
        function setCurrentState(obj, state)
            obj.CurrentState = state;
        end


        % ========== 보상 등록 ========== %
        function setReward(obj, outcome)

            if isempty(obj.RewardFunction)
                error("Agent:RewardFunctionNotSet", "RewardFunction이 등록되지 않았습니다.");
            end
            obj.PendingReward = obj.RewardFunction(outcome);
        end


        % ========== Transition 완성 및 Replay Buffer 저장 ========== %
        function completeTransition(obj)
            
            % 첫 번째 TimeSlot 예외처리
            if isempty(obj.PendingState) || isempty(obj.PendingAction) || isempty(obj.PendingReward) || isempty(obj.CurrentState)
                return;
            end

            % Replay Buffer 에러잡기
            if isempty(obj.ReplayBuffer)
                error("Agent:ReplayBufferNotSet", "ReplayBuffer가 설정되지 않았습니다.");
            end

            % Transition 저장 (O_t, a_t, r_t, O_{t+1}) 저장
            obj.ReplayBuffer.add(obj.PendingState, obj.PendingAction, obj.PendingReward, obj.CurrentState);

            % 저장 완료된 Pending Transition 초기화
            obj.PendingState = [];
            obj.PendingAction = [];
            obj.PendingReward = [];

        end


        % ========== DQN 학습 ========== %
        function lossValue = train(obj)
            
            lossValue = [];

            % Replay Buffer 확인
            if isempty(obj.ReplayBuffer)
                error( "Agent:ReplayBufferNotSet", "ReplayBuffer가 설정되지 않았습니다.");
            end


            % 1. Batch 추출
            batch = obj.ReplayBuffer.sample(obj.BatchSize);

                % Replay Buffer가 충분히 쌓이지 않았으면 학습하지 않음
            if isempty(batch)
                return;
            end


            % 2. Deep Learning 입력 방식으로 변환
            dlStates = dlarray(batch.States, "SSCB");
            dlNextStates = dlarray(batch.NextStates, "SSCB");
            dlRewards = dlarray(reshape(single(batch.Rewards), 1, obj.BatchSize), "CB");


            % 3. Target Q-Value 계산 (TargetNetwork 추론 -> max Next Q 추출 -> % Target 계산)
            dlTargetQValues = obj.calculateTargetQValues(dlNextStates, dlRewards);
            

            % 4. Current Q 계산 (QNetwork forward -> Action Q 추출), Loss계산, Gradient 계산
            [loss, gradients] = dlfeval(@(qNetwork, states, actions, targets)  ...
                obj.modelGradients(qNetwork, states, actions, targets), obj.QNetwork, dlStates, batch.Actions, dlTargetQValues);


            % 5. Weight Update
            obj.TrainingStep = obj.TrainingStep + 1;
            [obj.QNetwork, obj.AverageGradients, obj.AverageSquaredGradients] = adamupdate( ...
                obj.QNetwork, gradients, obj.AverageGradients, obj.AverageSquaredGradients, obj.TrainingStep, obj.LearningRate);


            % 6. Target Network 갱신
            if mod(obj.TrainingStep, obj.TargetUpdateFrequency) == 0
                obj.TargetNetwork = obj.QNetwork;
            end


            lossValue = double(extractdata(loss));






        end

        % ========== Target Q-Value 계산 ========== %
        function dlTargetQValues = calculateTargetQValues(obj, dlNextStates, dlRewards)
            % O_{t+1}에서 각 행동의 Q-value 계산
            dlNextQValues = predict(obj.TargetNetwork, dlNextStates);
            dlMaxNextQValues = max(dlNextQValues, [], 1);

            % Bellman Target ->  y_t = r_t + gamma × max_a Q_target(O_{t+1}, a)
                % 현재 행동의 가치 = 이번 행동으로 즉시 받은 보상 + 다음 상태에서 가장 좋아보이는 행동의 미래 가치
            dlTargetQValues = dlRewards + single(obj.DiscountFactor) .* dlMaxNextQValues;
        end


        % ========== Current Q, Loss, Gradient 계산 ========== %
        function [loss, gradients] = modelGradients(obj, qNetwork, dlStates, actions, dlTargetQValues)
        
            % Current Q 계산 ->  O_t에서 모든 행동의 Q-Value 계산
            dlCurrentQValues = forward(qNetwork, dlStates);
            batchSize = numel(actions);


            % 실제 선택했던 Action Q-value 가져오기
            actions = double(actions(:))';
            actionIndices = sub2ind([obj.NumActions, batchSize], actions, 1:batchSize);
            dlSelectedQValues = dlCurrentQValues(actionIndices);
            dlSelectedQValues = reshape(dlSelectedQValues, 1, batchSize);

            
            % Loss 계산
            loss = mean((dlSelectedQValues - dlTargetQValues).^2, "all");

            % Gradient 계산
            gradients = dlgradient(loss, qNetwork.Learnables);
        end


    end
end