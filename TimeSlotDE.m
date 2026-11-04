classdef TimeSlotDE
    % TimeSlotDE  (DQN Estimate)
    %
    % ================================================================
    % RF Observation + Oracle Action/Occupancy + SINR-Estimated Reward
    % ================================================================
    %
    % Target Agent:
    %   - 실제 환경에서 DQN 학습
    %   - 실제 HARQ ACK/NACK을 reward로 사용
    %
    % APJ Shadow Agent:
    %   - APJ 위치에서 RF observation 수행
    %   - Target actual action: Oracle
    %   - Occupancy: 0벡터 (target = first beam, rho_T = 0)
    %   - Reward:
    %       APJ가 자기 위치에서 추정한 Target SINR 기반 Pseudo-HARQ
    %
    % Attack:
    %   - ReconnaissanceDuration 이후 시작
    %   - TopKJam = 1: Top-1 prediction만 재밍
    %   - TopKJam = 2: Top-1 + Top-2 prediction 동시 재밍
    %
    % Baseline:
    %   - EnableJamming = false
    %   - reconnaissance / prediction / Shadow learning은 그대로 수행
    %   - 실제 RF jamming packet만 주입하지 않음
    %
    % 중요:
    %   isAttackPhase
    %       = reconnaissance 이후 evaluation 구간
    %
    %   isJammingActive
    %       = 실제 RF jamming 활성 여부
    %
    % 따라서 No-Attack baseline에서도 isAttackPhase=true가 될 수 있지만,
    % EnableJamming=false이면 실제 JAMMING packet은 절대 발생하지 않는다.

    properties
        ReconnaissanceDuration

        % 1 = Top-1
        % 2 = Top-1 + Top-2
        TopKJam

        % 실제 RF jamming 활성화 여부
        EnableJamming = true

        % 슬롯별 디버그 출력 (Target/Shadow Q 비교, reward 로그).
        % 배치 실험(final*.m)에서는 false로 두어 콘솔 출력을 끈다.
        Verbose = false
    end

    methods

        %% ============================================================
        % Constructor
        % =============================================================
        function obj = TimeSlotDE(topKJam, reconnaissanceDuration)

            % ---------------------------------------------------------
            % Top-K 설정
            % ---------------------------------------------------------
            if nargin < 1 || isempty(topKJam)
                topKJam = 2;
            end

            % ---------------------------------------------------------
            % Reconnaissance Duration
            %
            % 주의:
            % 기존처럼 여기서 env;를 다시 호출하지 않는다.
            %
            % final2.m에서 env를 한 번 호출한 뒤
            % trial별 RNG seed를 설정하므로,
            % 여기서 env를 다시 호출하면 RNG seed가 덮일 수 있다.
            % ---------------------------------------------------------
            if nargin < 2 || isempty(reconnaissanceDuration)
                error("TimeSlotDE:MissingReconnaissanceDuration", "reconnaissanceDuration을 생성자에 전달해야 합니다.");
            end

            obj.TopKJam = topKJam;
            obj.ReconnaissanceDuration = reconnaissanceDuration;
        end

        %% ============================================================
        % Main Time-Slot Execution
        % =============================================================
        function [divergenceLog, channelLog] = run(...
                obj, ...
                slotIndex, ...
                UTs, ...
                Satellite, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog)

            %% ========================================================
            % 1. Time Slot Header
            % =========================================================
            % DebugHelper.printTimeSlot(slotIndex);

            %% ========================================================
            % 2. Channel 초기화
            % =========================================================
            obj.clearChannels(ServiceChannels, ControlChannels);

            %% ========================================================
            % 3. Satellite Beam Action Selection
            % =========================================================
            currentSlotOccupancy = zeros(1, numel(ServiceChannels));
            targetBeam = [];
            targetAgent = [];
            targetState = [];
            targetOccupancy = [];
            targetAction = [];
            targetPrevState = [];
            targetPrevOccupancy = [];
            targetPrevAction = [];
            targetPrevReward = [];
            targetNextState = [];
            targetNextOccupancy = [];
            lossTarget = [];

            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);
                state = beam.StateManager.getState();
                beam.StateManager.setCurrentOccupancy(currentSlotOccupancy);
                occupancy = beam.StateManager.getCurrentOccupancy();

                % -----------------------------------------------------
                % Target 이전 transition 정보 저장
                % -----------------------------------------------------
                if beamIndex == targetBeamIndex
                    targetBeam = beam;
                    targetAgent = beam.Agent;
                    targetPrevState = beam.Agent.PendingState;
                    targetPrevOccupancy = beam.Agent.PendingOccupancy;
                    targetPrevAction = beam.Agent.PendingAction;
                    targetPrevReward = beam.Agent.PendingReward;
                    targetNextState = state;
                    targetNextOccupancy = occupancy;
                end

                % -----------------------------------------------------
                % Agent current state / occupancy 설정
                % -----------------------------------------------------
                beam.Agent.setCurrentState(state);
                beam.Agent.setCurrentOccupancy(occupancy);

                % -----------------------------------------------------
                % 이전 transition 완성
                % -----------------------------------------------------
                beam.Agent.completeTransition();

                % -----------------------------------------------------
                % DQN train
                % -----------------------------------------------------
                [lossValue, trainingInfo] = beam.Agent.train();

                if beamIndex == targetBeamIndex
                    lossTarget = lossValue;

                    % DebugHelper.printAgentTraining(...
                    %     beam, ...
                    %     lossValue, ...
                    %     trainingInfo);
                end

                % -----------------------------------------------------
                % 현재 Action 선택
                % -----------------------------------------------------
                [selectedChannel, ...
                 selectionMethod, randomValue, qValues] = beam.Agent.selectAction(state, occupancy);
                beam.SelectedChannel = selectedChannel;
                currentSlotOccupancy(selectedChannel) = currentSlotOccupancy(selectedChannel) + 1;

                % -----------------------------------------------------
                % Target 정보 저장
                % -----------------------------------------------------
                if beamIndex == targetBeamIndex
                    targetState = state;
                    targetOccupancy = occupancy;
                    targetAction = selectedChannel;

                    % DebugHelper.printTargetActionSelection(...
                    %     slotIndex, ...
                    %     beam, ...
                    %     selectedChannel, ...
                    %     selectionMethod, ...
                    %     randomValue, ...
                    %     qValues);

                    channelEntry.slot = slotIndex;
                    channelEntry.channel = selectedChannel;
                    channelEntry.epsilon = beam.Agent.Epsilon;
                    channelEntry.method = selectionMethod;

                    if isempty(qValues)
                        channelEntry.qValues = NaN(1, beam.Agent.NumActions);
                    else
                        channelEntry.qValues = qValues(:)';
                    end

                    channelLog(end + 1) = channelEntry; %#ok<AGROW>
                end
            end

            if isempty(targetAgent)
                error("TimeSlotDE:TargetAgentNotFound", "Target Beam %d의 Agent를 찾지 못했습니다.", targetBeamIndex);
            end

            %% ========================================================
            % 4. APJ Attack Decision
            % =========================================================

            % ---------------------------------------------------------
            % 이전 슬롯에서 예측했던 next action
            % ---------------------------------------------------------
            previousPredictedChannel = apjd.PredictedChannel;
            previousPredictedQValues = apjd.PredictedQValues;

            % ---------------------------------------------------------
            % Top-2 prediction 계산
            % ---------------------------------------------------------
            previousPredictedTop2Channel = [];

            if obj.TopKJam >= 2 && ~isempty(previousPredictedQValues)
                [~, rankedChannels] = sort(previousPredictedQValues(:), 'descend');

                if numel(rankedChannels) >= 2
                    previousPredictedTop2Channel = rankedChannels(2);
                end
            end

            % ---------------------------------------------------------
            % Evaluation / Attack Phase
            %
            % reconnaissance 이후이면 true.
            %
            % Baseline에서도 이 값은 true가 될 수 있다.
            % ---------------------------------------------------------
            isAttackPhase = slotIndex > obj.ReconnaissanceDuration;

            % ---------------------------------------------------------
            % 실제 RF Jamming 여부
            % ---------------------------------------------------------
            isJammingActive = isAttackPhase && obj.EnableJamming;

            % ---------------------------------------------------------
            % APJ가 "공격한다면" 선택했을 candidate channels
            %
            % Baseline에서도 prediction 자체는 계속 수행할 수 있음.
            % ---------------------------------------------------------
            candidateJammingChannels = [];

            if isAttackPhase && ~isempty(previousPredictedChannel)
                candidateJammingChannels = previousPredictedChannel;

                if ~isempty(previousPredictedTop2Channel) && ...
                        previousPredictedTop2Channel ~= previousPredictedChannel

                    candidateJammingChannels = ...
                        [candidateJammingChannels, previousPredictedTop2Channel]; %#ok<AGROW>
                end
            end

            % ---------------------------------------------------------
            % 실제 재밍 채널 결정
            % ---------------------------------------------------------
            if isJammingActive && ~isempty(candidateJammingChannels)
                jammingChannels = candidateJammingChannels;

                % 기존 APJ 내부 단일 JammingChannel property 유지
                %
                % Top-K 전체 채널은 jammingChannels 로 따로 관리하고,
                % 대표값은 첫 번째 채널을 저장.
                apjd.JammingChannel = jammingChannels(1);
            else
                % -----------------------------------------------------
                % No-Attack baseline 또는 reconnaissance phase
                % -----------------------------------------------------
                jammingChannels = [];
                apjd.JammingChannel = [];
            end

            % ---------------------------------------------------------
            % Prediction Accuracy 기록
            %
            % 실제 jamming 여부와 관계없이 prediction 자체는 기록 가능.
            % ---------------------------------------------------------
            if obj.Verbose && ~isempty(previousPredictedChannel)
                DebugHelper.recordAPJPrediction(...
                    slotIndex, previousPredictedChannel, targetAction, numel(ServiceChannels));
            end

            %% ========================================================
            % 5. Satellite -> UT Downlink DATA
            % =========================================================
            dataPackets = cell(1, numel(Satellite.Beams));

            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);

                dataPackets{beamIndex} = ...
                    Packet(...
                        PacketType.DATA, ...
                        NodeType.Satellite, ...
                        Satellite.Id, ...
                        NodeType.UT, beam.AssociatedUTId, beam.Id, ChannelType.Service, beam.SelectedChannel);
            end

            for beamIndex = 1:numel(dataPackets)
                packet = dataPackets{beamIndex};
                ServiceChannels(packet.ChannelId).addPacket(packet);
            end

            %% ========================================================
            % 5.5. APJ 실제 RF Jamming Packet 주입
            % =========================================================
            %
            % 중요:
            %
            %   isAttackPhase     = 평가 구간
            %   isJammingActive   = 실제 공격 활성 여부
            %
            % Baseline에서는 EnableJamming=false이므로
            % 이 블록에 절대 진입하지 않는다.
            % =========================================================

            if isJammingActive && ~isempty(jammingChannels)
                targetBeamId = Satellite.Beams(targetBeamIndex).Id;

                for jammingChannel = jammingChannels
                    jamPacket = ...
                        Packet(...
                            PacketType.JAMMING, ...
                            NodeType.APJ, ...
                            apjd.Id, ...
                            NodeType.UT, apjd.TargetUTId, targetBeamId, ChannelType.Service, jammingChannel);
                    ServiceChannels(jammingChannel).addPacket(jamPacket);
                end
            end

            %% ========================================================
            % 6. Target UT / APJ RF Observation
            % =========================================================

            targetUT = UTs(apjd.TargetUTId);
            targetUTRFObservation = targetUT.ObservationManager.observe(ServiceChannels, Satellite);
            apjdRFObservation = apjd.ObservationManager.observe(ServiceChannels, Satellite);

            %#ok<NASGU>
            % targetUTRFObservation은 현재 직접 사용하지 않아도
            % validation/debug 용으로 유지.

            %% ========================================================
            % 6.5. APJ SINR Estimation -> Pseudo HARQ
            % =========================================================
            %
            % DATA와 JAMMING packet이 ServiceChannels에 모두 반영된 이후
            % APJ 위치에서 Target SINR을 추정.
            %
            % Baseline:
            %   JAMMING packet 없음
            %
            % Attack:
            %   JAMMING packet 포함
            % =========================================================

            estimatedSINR_dB = apjd.estimateTargetSINR(ServiceChannels, Satellite, targetUT);
            estimatedPacketType = apjd.generatePseudoHARQ(estimatedSINR_dB);

            if isempty(estimatedPacketType)
                % Target packet을 찾지 못한 예외
                estimatedOutcome = NaN;
            else
                estimatedOutcome = double(estimatedPacketType == PacketType.ACK);
            end

            %% ========================================================
            % 7. APJ Shadow Agent
            % =========================================================

            shadowAgent = apjd.Agent;
            shadowState = apjd.StateManager.getState();

            % Occupancy: target이 fixed decision order의 첫 번째 beam이므로
            % preceding-beam occupancy가 없음 -> rho_T(t) = 0 (논문 II-B).
            % oracle 복사가 아니라 명시적 0벡터를 사용한다.
            shadowOccupancy = zeros(1, numel(ServiceChannels));
            shadowAgent.setCurrentState(shadowState);
            shadowAgent.setCurrentOccupancy(shadowOccupancy);

            %% ========================================================
            % 7-1. Previous Shadow Transition Complete
            % =========================================================
            shadowAgent.completeTransition();

            %% ========================================================
            % 7-2. Shadow DQN Training
            % =========================================================
            [lossShadow, trainingInfoShadow] = shadowAgent.train();

            %#ok<NASGU>
            % trainingInfoShadow는 debug용

            %% ========================================================
            % 7-3. Target Actual Action Oracle 제공
            % =========================================================
            shadowAgent.observeAction(shadowState, shadowOccupancy, targetAction);
            apjd.ObservedChannel = targetAction;

            %% ========================================================
            % 7-4. Target / Shadow Q-vector
            % =========================================================

            dlTargetState = targetAgent.convertStateToDLArray(targetState);
            dlTargetOccupancy = targetAgent.convertOccupancyToDLArray(targetOccupancy);
            qTarget = extractdata(predict(targetAgent.QNetwork, dlTargetState, dlTargetOccupancy));
            qTarget = double(qTarget(:));
            dlShadowState = shadowAgent.convertStateToDLArray(shadowState);
            dlShadowOccupancy = shadowAgent.convertOccupancyToDLArray(shadowOccupancy);
            qShadow = extractdata(predict(shadowAgent.QNetwork, dlShadowState, dlShadowOccupancy));
            qShadow = double(qShadow(:));

            %% ========================================================
            % 7-5. Q Similarity Metrics
            % =========================================================

            [~, greedyTarget] = max(qTarget);
            [~, greedyShadow] = max(qShadow);
            qCosSim = dot(qTarget, qShadow) / (norm(qTarget) * norm(qShadow) + eps);
            argmaxMatch = double(greedyTarget == greedyShadow);
            qL2Dist = norm(qTarget - qShadow);
            weightDiffNorm = TimeSlotDE.computeWeightDiffNorm(targetAgent.QNetwork, shadowAgent.QNetwork);
            weightNormTarget = TimeSlotDE.computeNetworkNorm(targetAgent.QNetwork);
            weightNormShadow = TimeSlotDE.computeNetworkNorm(shadowAgent.QNetwork);

            % ---------------------------------------------------------
            % Debug output
            % ---------------------------------------------------------
            if obj.Verbose
                DebugHelper.printTargetVsShadowDQN(...
                    slotIndex, ...
                    targetAction, ...
                    qTarget, ...
                    qShadow, ...
                    greedyTarget, ...
                    greedyShadow, qCosSim, qL2Dist, weightDiffNorm, weightNormTarget, weightNormShadow);

                fprintf(...
                    ['  [TimeSlotDE Reward Source] : ', ...
                     'SINR ESTIMATE ', '(estimatedOutcome=%s)\n'], mat2str(estimatedOutcome));
            end

            %% ========================================================
            % 7-6. Divergence Log
            % =========================================================

            if isempty(lossTarget)
                lossTargetLog = NaN;
            else
                lossTargetLog = lossTarget;
            end

            if isempty(lossShadow)
                lossShadowLog = NaN;
            else
                lossShadowLog = lossShadow;
            end

            entry.slot = slotIndex;
            entry.lossA = lossTargetLog;
            entry.lossB = lossShadowLog;
            entry.qCosSim = qCosSim;
            entry.argmaxMatch = argmaxMatch;
            entry.weightDiffNorm = weightDiffNorm;
            entry.weightNormA = weightNormTarget;
            entry.weightNormB = weightNormShadow;
            entry.qA = qTarget(:)';
            entry.qB = qShadow(:)';
            entry.qL2Dist = qL2Dist;
            entry.observedChannel = targetAction;
            entry.actualACK = NaN;
            entry.estimatedOutcome = estimatedOutcome;

            % Evaluation phase 여부
            entry.isAttackPhase = isAttackPhase;

            % 실제 RF jamming이 실행된 채널만 기록
            %
            % Baseline에서는 []
            entry.jammingChannels = jammingChannels;
            divergenceLog(end + 1) = entry; %#ok<AGROW>

            %% ========================================================
            % 8. UT HARQ
            % =========================================================

            harqResults = cell(1, numel(UTs));
            sinrResults_dB = zeros(1, numel(UTs));
            targetPacketType = [];
            targetSINR_dB = [];

            for utIndex = 1:numel(UTs)
                [packetType, SINR_dB] = ...
                    UTs(utIndex).performHARQ(ServiceChannels, ControlChannels, Satellite, apjd);
                harqResults{utIndex} = packetType;
                sinrResults_dB(utIndex) = SINR_dB;

                if utIndex == apjd.TargetUTId
                    targetPacketType = packetType;
                    targetSINR_dB = SINR_dB;
                end
            end

            %% ========================================================
            % 9. Beam Feedback / Target Reward
            % =========================================================

            actualACK = false(1, numel(Satellite.Beams));

            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);
                actualACK(beamIndex) = beam.receiveFeedback(ControlChannels, Satellite);

                % Target beam 포함 모든 정상 Agent는
                % 실제 HARQ reward 사용
                beam.Agent.setReward(actualACK(beamIndex));
            end

            %% ========================================================
            % 10. Shadow Reward = Estimated Pseudo-HARQ
            % =========================================================

            targetOutcome = actualACK(targetBeamIndex);

            if isnan(estimatedOutcome)
                % 예외 시 NACK 처리
                shadowRewardOutcome = false;
            else
                shadowRewardOutcome = logical(estimatedOutcome);
            end

            shadowAgent.setReward(shadowRewardOutcome);

            if shadowRewardOutcome == targetOutcome
                matchLabel = "MATCH";
            else
                matchLabel = "MISMATCH";
            end

            if obj.Verbose
                fprintf(...
                    ['  [TimeSlotDE Reward] : ', ...
                     'Shadow=%s (estimated) ', ...
                     'vs Target=%s (actual) ', ...
                     '-> %s\n'], ...
                    mat2str(shadowRewardOutcome), mat2str(targetOutcome), matchLabel);
            end

            %% ========================================================
            % Target UT Result Logging
            % =========================================================

            DebugHelper.recordTargetUTOutcome(...
                slotIndex, targetPacketType, targetSINR_dB, obj.ReconnaissanceDuration);

            %% ========================================================
            % 11. APJ StateManager Update
            % =========================================================
            %
            % O : RF observation
            % A : Target actual action Oracle
            % H : Target actual packet type Oracle
            % =========================================================

            if isempty(apjdRFObservation)
                warning(...
                    "TimeSlotDE:EmptyAPJRFObservation", ...
                    "Slot %d에서 APJ RF observation이 비어 있습니다.", ...
                    slotIndex);
            else
                apjd.StateManager.update(apjdRFObservation, targetAction, estimatedPacketType);
            end

            %% ========================================================
            % 12. Actual ACK Log
            % =========================================================

            if ~isempty(divergenceLog) && divergenceLog(end).slot == slotIndex
                divergenceLog(end).actualACK = double(targetOutcome);
            end

            %% ========================================================
            % 13. NEXT-SLOT Shadow Prediction
            % =========================================================

            nextShadowState = apjd.StateManager.getState();

            % 예측 입력 occupancy도 동일하게 0벡터 (Eq. 5의 Q_J(s~_J(t+1), 0; theta_J))
            predictionOccupancy = zeros(1, numel(ServiceChannels));

            [predictedAction, predictedQValues] = ...
                shadowAgent.predictAction(nextShadowState, predictionOccupancy);
            apjd.PredictedChannel = predictedAction;
            apjd.PredictedQValues = predictedQValues;
        end

        %% ============================================================
        % Channel Clear
        % =============================================================
        function clearChannels(~, ServiceChannels, ControlChannels)

            for channelIndex = 1:numel(ServiceChannels)
                ServiceChannels(channelIndex).clearPacket();
            end

            for channelIndex = 1:numel(ControlChannels)
                ControlChannels(channelIndex).clearPacket();
            end
        end
    end

    %% ================================================================
    % Static Utility Methods
    % =================================================================
    methods (Static)

        %% ============================================================
        % Network Weight Difference Norm
        % =============================================================
        function normDiff = computeWeightDiffNorm(networkA, networkB)

            learnA = networkA.Learnables;
            learnB = networkB.Learnables;

            if height(learnA) ~= height(learnB)
                error("TimeSlotDE:NetworkStructureMismatch", "Target과 Shadow Network 구조가 다릅니다.");
            end

            sumSquares = 0;

            for learnableIndex = 1:height(learnA)
                valueA = double(extractdata(learnA.Value{ learnableIndex}));
                valueB = double(extractdata(learnB.Value{ learnableIndex}));

                if ~isequal(size(valueA), size(valueB))
                    error("TimeSlotDE:NetworkParameterSizeMismatch", "Target/Shadow parameter size가 다릅니다.");
                end

                difference = valueA(:) - valueB(:);
                sumSquares = sumSquares + sum(difference .^ 2);
            end

            normDiff = sqrt(sumSquares);
        end

        %% ============================================================
        % Network Norm
        % =============================================================
        function normValue = computeNetworkNorm(network)

            learnables = network.Learnables;
            sumSquares = 0;

            for learnableIndex = 1:height(learnables)
                value = double(extractdata(learnables.Value{ learnableIndex}));
                sumSquares = sumSquares + sum(value(:) .^ 2);
            end

            normValue = sqrt(sumSquares);
        end

        %% ============================================================
        % Phase String
        % =============================================================
        function text = phaseToString(isAttackPhase)

            if isAttackPhase
                text = "ATTACK";
            else
                text = "RECONNAISSANCE";
            end
        end
    end
end