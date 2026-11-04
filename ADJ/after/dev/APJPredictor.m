classdef APJPredictor < handle
    properties

        % ========== 기본 정보 ==========
        Owner                   % 자신을 소유한 APJ 객체
        NumChannels              % 채널 개수 (= 출력 클래스 개수)
        HistoryLength             % OAH 텐서의 시간축 길이(phi)

        % ========== 네트워크 & 학습 설정 ==========
        Network                  % 분류기 네트워크 (softmax 출력)
        TrainingBuffer            % APJTrainingBuffer — (state, label) 쌍 축적
        BatchSize
        LearningRate

        % ========== Training (Adam Optimizer 상태) ==========
        TrainingStep

        AverageGradients
        AverageSquaredGradients

        % ===== Pending: 이번 슬롯 관측을 완성하기 전 임시 보관 =====
        PendingState             % 직전 슬롯에서 관측한 (O,A,H) — 아직 레이블(다음 채널)을 못 받은 상태

    end

    methods
        % ========== 생성자 ==========
        function obj = APJPredictor(owner)
            env;

            obj.Owner = owner;
            obj.NumChannels = numChannels;
            obj.HistoryLength = phi;

            obj.BatchSize = apjBatchSize;
            obj.LearningRate = apjLearnRate;

            obj.TrainingBuffer = APJTrainingBuffer(apjReplayBufferCapacity);

            obj.TrainingStep = 0;
            obj.AverageGradients = [];
            obj.AverageSquaredGradients = [];

            obj.PendingState = [];

            % ========== Network — Beam과 동일한 패턴: 실제 StateManager 출력에서 shape을 가져옴 ==========
            inputSize = size(owner.StateManager.getState());

            if numel(inputSize) == 2
                inputSize = [inputSize 1];
            end

            obj.Network = obj.createNetwork(inputSize);
        end


        % ========== Pending State 등록 ==========
        function setPendingState(obj, state)
            obj.PendingState = state;
        end


        % ========== 다음 슬롯의 실제 채널이 확정되면 학습 쌍 완성 ==========
        function completeTrainingPair(obj, actualChannel)

            if isempty(obj.PendingState)
                return;
            end

            if isempty(obj.TrainingBuffer)
                error("APJPredictor:TrainingBufferNotSet", "TrainingBuffer가 설정되지 않았습니다.");
            end

            obj.TrainingBuffer.add(obj.PendingState, actualChannel);

            obj.PendingState = [];
        end


        % ========== 다음 채널 예측 (추론, Top-K) ==========
        function [predictedChannels, probabilities] = predictChannel(obj, state, topK)
            if nargin < 3
                topK = 1;
            end
        
            dlState = obj.convertStateToDLArray(state);
        
            dlProbabilities = predict(obj.Network, dlState);
        
            probabilities = extractdata(dlProbabilities);
            probabilities = probabilities(:);
        
            [~, sortedIndices] = sort(probabilities, 'descend');
            predictedChannels = sortedIndices(1:min(topK, numel(sortedIndices)))';
        end


        % ========== State를 네트워크 입력으로 변환 ==========
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


        % ========== Behavior Cloning 학습 ==========
        function [lossValue, trainingInfo] = train(obj)
            lossValue = [];
            trainingInfo = struct("MeanTrueProbability", [], "Accuracy", []);

            % TrainingBuffer 확인
            if isempty(obj.TrainingBuffer)
                error("APJPredictor:TrainingBufferNotSet", "TrainingBuffer가 설정되지 않았습니다.");
            end

            % TrainingBuffer가 충분히 쌓이지 않았으면 학습하지 않음
            if ~obj.TrainingBuffer.isReady(obj.BatchSize)
                return;
            end

            % 1. Batch 추출
            [states, labels] = obj.TrainingBuffer.sample(obj.BatchSize);

            % 2. Deep Learning 입력 방식으로 변환
            stateBatch = obj.stackStates(states);
            dlStates = dlarray(single(stateBatch), "SSCB");

            labelsRow = double(labels(:))';
            batchSize = numel(labelsRow);
            labelIndices = sub2ind([obj.NumChannels, batchSize], labelsRow, 1:batchSize);

            % 3. Loss / Gradient 계산
            [loss, gradients, dlProbabilities] = dlfeval(@(network, inputStates, inputLabelIndices) obj.modelGradients( ...
                    network, inputStates, inputLabelIndices), obj.Network, dlStates, labelIndices);

            % 4. Network Weight Update
            obj.TrainingStep = obj.TrainingStep + 1;
            [obj.Network, obj.AverageGradients, obj.AverageSquaredGradients] = adamupdate( ...
                obj.Network, gradients, obj.AverageGradients, obj.AverageSquaredGradients, obj.TrainingStep, obj.LearningRate);

            % 5. Loss / Accuracy 반환
            lossValue = double(extractdata(loss));

            probabilities = extractdata(dlProbabilities);          % NumChannels x BatchSize
            [~, predictedLabels] = max(probabilities, [], 1);

            selectedProbabilities = probabilities(labelIndices);

            trainingInfo.MeanTrueProbability = mean(selectedProbabilities, "all");
            trainingInfo.Accuracy = mean(predictedLabels == labelsRow);

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
            stateBatch = zeros(stateHeight, stateWidth, stateChannels, batchSize, "single");

            for batchIndex = 1:batchSize
                state = states{batchIndex};

                if ndims(state) == 2
                    state = reshape(state, size(state, 1), size(state, 2), 1);
                end

                stateBatch(:, :, :, batchIndex) = single(state);
            end
        end

    end


    methods (Access = private)

        % ========== 분류기 네트워크 정의 ==========
        function network = createNetwork(obj, inputSize)
            layers = [
                imageInputLayer(inputSize, Normalization="none", Name="oah_input")
                convolution2dLayer([10 4], 16, Stride=2, Padding="same", Name="conv1")
                reluLayer(Name="relu1")
                fullyConnectedLayer(128, Name="fc1")
                reluLayer(Name="relu2")
                fullyConnectedLayer(obj.NumChannels, Name="fc2")
                softmaxLayer(Name="softmax")
            ];
            network = dlnetwork(layers);
        end


        % ========== Cross-Entropy Loss / Gradient 계산 ==========
        function [loss, gradients, dlProbabilities] = modelGradients(obj, network, dlStates, labelIndices)

            % 전체 채널에 대한 확률 분포
            dlProbabilities = forward(network, dlStates);

            % 실제 정답 채널의 확률만 추출
            dlSelectedProbabilities = dlProbabilities(labelIndices);
            dlSelectedProbabilities = reshape(dlSelectedProbabilities, 1, []);

            % Cross-Entropy Loss: -log(p_true)
            loss = -mean(log(dlSelectedProbabilities + eps), "all");

            % Gradient
            gradients = dlgradient(loss, network.Learnables);
        end

    end
end