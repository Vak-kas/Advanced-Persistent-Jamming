classdef HybridDQNAgent < handle
    properties
        id
        K
        phi

        historyBuffer
        replayBuffer
        experiencePoolCapacity

        net_u
        net_j

        % ===== Target Networks =====
        target_net_u
        target_net_j
        targetUpdatePeriod

        gamma
        eta
        epsilon

        batchSize
        learnRate
    end

    properties(Access=private)
        iteration_u
        iteration_j

        avgGrad_u
        avgSqGrad_u

        avgGrad_j
        avgSqGrad_j
    end

    methods
        % ========== Agent 생성자 ==========
        function obj = HybridDQNAgent(id, K, phi, experiencePoolCapacity, gamma, eta, epsilon, batchSize, learnRate)
            obj.id = id;
            obj.K = K;
            obj.phi = phi;

            obj.experiencePoolCapacity = experiencePoolCapacity;
            obj.gamma = gamma;
            obj.eta = eta;
            obj.epsilon = epsilon;
            obj.batchSize = batchSize;
            obj.learnRate = learnRate;

            obj.historyBuffer = zeros(phi, K);
            obj.replayBuffer = {};

            % ===== Online Networks =====
            obj.net_u = obj.createQNetwork();
            obj.net_j = obj.createQNetwork();

            % 논문: same structure and initial parameters
            obj.net_j.Learnables = obj.net_u.Learnables;

            % ===== Target Networks =====
            obj.target_net_u = obj.net_u;
            obj.target_net_j = obj.net_j;

            % 몇 번 학습마다 target network를 online network로 동기화할지
            % 우선 50 추천. 너무 크면 느리고, 너무 작으면 target network 효과가 약함.
            obj.targetUpdatePeriod = 20;

            obj.iteration_u = 0;
            obj.iteration_j = 0;

            obj.avgGrad_u = [];
            obj.avgGrad_j = [];

            obj.avgSqGrad_u = [];
            obj.avgSqGrad_j = [];
        end

        % ========== Q Network 생성 ==========
        function net = createQNetwork(obj)
            layers = [
                imageInputLayer([obj.phi obj.K 1], Normalization="none", Name="spectrum_waterfall_input")

                convolution2dLayer([10 4], 16, Stride=2, Padding="same", Name="Convolution")
                reluLayer(Name="relu_conv")

                fullyConnectedLayer(128, Name="fc1")
                reluLayer(Name="relu_fc1")

                fullyConnectedLayer(obj.K, Name="fc2")
            ];

            lgraph = layerGraph(layers);
            net = dlnetwork(lgraph);
        end

        % ========== 센싱 결과 업데이트 ==========
        function updateObservation(obj, o_t)

            if size(o_t, 1) ~= 1
                o_t = o_t(:).';
            end

            if length(o_t) ~= obj.K
                error("Observation size mismatch. Expected 1 x %d", obj.K);
            end

            obj.historyBuffer(2:end, :) = obj.historyBuffer(1:end-1, :);
            obj.historyBuffer(1, :) = o_t;
        end

        % ========== 현재 Observation 반환 ==========
        function O_t = getObservation(obj)
            O_t = obj.historyBuffer;
        end

        % ========== 현재 Q 예측 ==========
        function [q_u, q_j, compositeQ] = predictQ(obj)
            O_t = obj.getObservation();

            X = reshape(single(O_t), [obj.phi obj.K 1 1]);
            X = dlarray(X, "SSCB");

            q_u = extractdata(predict(obj.net_u, X));
            q_j = extractdata(predict(obj.net_j, X));

            q_u = q_u(:).';
            q_j = q_j(:).';

            compositeQ = obj.eta * q_j + (1 - obj.eta) * q_u;
        end

        % ========== 채널 선택 ==========
        function action = selectAction(obj)

            if rand < obj.epsilon
                action = randi(obj.K);
                return;
            end

            [~, ~, compositeQ] = obj.predictQ();

            maxQ = max(compositeQ);
            candidates = find(compositeQ == maxQ);
            action = candidates(randi(length(candidates)));
        end

        % ========== Experience 저장 ==========
        function storeExperience(obj, O_t, action, r_u, r_j, O_next)
            exp = Experience(O_t, action, r_u, r_j, O_next);

            currentSize = length(obj.replayBuffer);

            if currentSize < obj.experiencePoolCapacity
                obj.replayBuffer{end+1} = exp;
            else
                obj.replayBuffer(1:end-1) = obj.replayBuffer(2:end);
                obj.replayBuffer{end} = exp;
            end
        end

        % ========== Train ==========
        function train(obj)

            if length(obj.replayBuffer) < obj.batchSize
                return;
            end

            numExperiences = length(obj.replayBuffer);
            sampledIndices = randperm(numExperiences, obj.batchSize);

            O_t_batch    = zeros(obj.phi, obj.K, 1, obj.batchSize, 'single');
            a_t_batch    = zeros(obj.batchSize, 1);
            r_u_batch    = zeros(obj.batchSize, 1, 'single');
            r_j_batch    = zeros(obj.batchSize, 1, 'single');
            O_next_batch = zeros(obj.phi, obj.K, 1, obj.batchSize, 'single');

            for i = 1:obj.batchSize
                expObj = obj.replayBuffer{sampledIndices(i)};

                O_t_batch(:, :, 1, i)    = expObj.O_t;
                a_t_batch(i)             = expObj.action;
                r_u_batch(i)             = expObj.r_u;
                r_j_batch(i)             = expObj.r_j;
                O_next_batch(:, :, 1, i) = expObj.O_next;
            end

            dl_O_t    = dlarray(O_t_batch, 'SSCB');
            dl_O_next = dlarray(O_next_batch, 'SSCB');

            % ===== net_u 학습: target_net_u 사용 =====
            obj.iteration_u = obj.iteration_u + 1;

            [loss_u, gradients_u] = dlfeval( ...
                @obj.computeLoss, ...
                obj.net_u, ...
                obj.target_net_u, ...
                dl_O_t, ...
                a_t_batch, ...
                r_u_batch, ...
                dl_O_next ...
            );

            [obj.net_u, obj.avgGrad_u, obj.avgSqGrad_u] = adamupdate( ...
                obj.net_u, ...
                gradients_u, ...
                obj.avgGrad_u, ...
                obj.avgSqGrad_u, ...
                obj.iteration_u, ...
                obj.learnRate ...
            );

            % ===== net_j 학습: target_net_j 사용 =====
            obj.iteration_j = obj.iteration_j + 1;

            [loss_j, gradients_j] = dlfeval( ...
                @obj.computeLoss, ...
                obj.net_j, ...
                obj.target_net_j, ...
                dl_O_t, ...
                a_t_batch, ...
                r_j_batch, ...
                dl_O_next ...
            );

            [obj.net_j, obj.avgGrad_j, obj.avgSqGrad_j] = adamupdate( ...
                obj.net_j, ...
                gradients_j, ...
                obj.avgGrad_j, ...
                obj.avgSqGrad_j, ...
                obj.iteration_j, ...
                obj.learnRate ...
            );

            % ===== Target Network 주기적 동기화 =====
            if mod(obj.iteration_u, obj.targetUpdatePeriod) == 0
                obj.target_net_u.Learnables = obj.net_u.Learnables;
            end

            if mod(obj.iteration_j, obj.targetUpdatePeriod) == 0
                obj.target_net_j.Learnables = obj.net_j.Learnables;
            end
        end

        % ========== Loss 계산 ==========
        function [loss, gradients] = computeLoss(obj, onlineNet, targetNet, dl_O_t, a_t_batch, r_batch, dl_O_next)

            % 현재 Q-value: online network 사용
            q_current = forward(onlineNet, dl_O_t);
            q_current = reshape(q_current, obj.K, []);

            % Target Q-value: target network 사용
            q_next = predict(targetNet, dl_O_next);
            % q_next = predict(onlineNet, dl_O_next);
            q_next = extractdata(q_next);
            q_next = reshape(q_next, obj.K, []);

            max_q_next = max(q_next, [], 1);

            r_batch = single(r_batch(:).');
            target_q = r_batch + obj.gamma * single(max_q_next);
            target_q = dlarray(target_q);

            batchN = size(q_current, 2);
            a_t_batch = double(a_t_batch(:).');

            actionIdx = sub2ind([obj.K, batchN], a_t_batch, 1:batchN);
            q_predicted = q_current(actionIdx);

            loss = mean((q_predicted - target_q).^2, "all");

            gradients = dlgradient(loss, onlineNet.Learnables);
        end
    end
end