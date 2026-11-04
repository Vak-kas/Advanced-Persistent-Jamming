classdef TimeSlotD
    % TimeSlotD
    %
    % RF Observation + Oracle Action/Reward Shadow DQN
    %
    % Target:
    %   - 실제 BeamAgent
    %   - epsilon-greedy 실제 action
    %   - 실제 HARQ reward
    %
    % APJ Shadow:
    %   - APJ 위치 RF observation
    %   - Occupancy: Oracle
    %   - Action: Target actual action Oracle
    %   - HARQ/Reward: Target actual result Oracle
    %
    % 매 슬롯마다 같은 ServiceChannels를 Target UT와 APJD가 각각
    % observe()하여 채널별 RF 값을 DebugHelper에서 직접 비교한다.

    methods

        function obj = TimeSlotD()
        end

        function [divergenceLog, channelLog] = run(obj, slotIndex, UTs, Satellite, apjd, ...
                ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog)

            %% 1. Time Slot Header
            DebugHelper.printTimeSlot(slotIndex);

            %% 2. Channel 초기화
            obj.clearChannels(ServiceChannels, ControlChannels);

            %% 3. Satellite Beam Action Selection
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

                beam.Agent.setCurrentState(state);
                beam.Agent.setCurrentOccupancy(occupancy);
                beam.Agent.completeTransition();

                [lossValue, trainingInfo] = beam.Agent.train();

                if beamIndex == targetBeamIndex
                    lossTarget = lossValue;
                    DebugHelper.printAgentTraining(beam, lossValue, trainingInfo);
                end

                [selectedChannel, selectionMethod, randomValue, qValues] = ...
                    beam.Agent.selectAction(state, occupancy);

                beam.SelectedChannel = selectedChannel;
                currentSlotOccupancy(selectedChannel) = currentSlotOccupancy(selectedChannel) + 1;

                if beamIndex == targetBeamIndex
                    targetState = state;
                    targetOccupancy = occupancy;
                    targetAction = selectedChannel;

                    DebugHelper.printTargetActionSelection( ...
                        slotIndex, beam, selectedChannel, selectionMethod, randomValue, qValues);

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
                error("TimeSlotD:TargetAgentNotFound", ...
                    "Target Beam %d의 Agent를 찾지 못했습니다.", targetBeamIndex);
            end

            %% 4. Satellite -> UT Downlink DATA 전송
            dataPackets = cell(1, numel(Satellite.Beams));

            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);

                dataPackets{beamIndex} = Packet( ...
                    PacketType.DATA, NodeType.Satellite, Satellite.Id, ...
                    NodeType.UT, beam.AssociatedUTId, beam.Id, ...
                    ChannelType.Service, beam.SelectedChannel);
            end

            for beamIndex = 1:numel(dataPackets)
                packet = dataPackets{beamIndex};
                ServiceChannels(packet.ChannelId).addPacket(packet);
            end

            %% 5. Target UT와 APJD가 같은 순간 RF Observation 수행
            targetUT = UTs(apjd.TargetUTId);

            targetUTRFObservation = targetUT.ObservationManager.observe( ...
                ServiceChannels, Satellite);

            apjdRFObservation = apjd.ObservationManager.observe( ...
                ServiceChannels, Satellite);

            % 매 슬롯마다 RF observation vector를 한 줄로 직접 출력
            fprintf("\n============================================================\n");
            fprintf("RAW RF OBSERVATION VECTOR - SLOT %d\n", slotIndex);
            fprintf("============================================================\n");
            fprintf("  UT1 RF Observation       : %s\n", ...
                mat2str(double(targetUTRFObservation(:))', 6));
            fprintf("  APJ RF Observation      : %s\n", ...
                mat2str(double(apjdRFObservation(:))', 6));
            fprintf("============================================================\n");

            DebugHelper.printRFObservationComparison( ...
                slotIndex, targetUT, apjd, targetUTRFObservation, apjdRFObservation);

            %% 6. APJ Shadow Agent
            shadowAgent = apjd.Agent;

            % 이전 슬롯 마지막 update()까지 반영된 APJ state
            shadowState = apjd.StateManager.getState();

            % Occupancy는 이번 단계에서 Oracle
            shadowOccupancy = targetOccupancy;

            shadowAgent.setCurrentState(shadowState);
            shadowAgent.setCurrentOccupancy(shadowOccupancy);

            %% 6-1. RF state 차이 / Oracle component 확인
            if ~isempty(targetPrevState) && ~isempty(shadowAgent.PendingState)
                DebugHelper.printRFOracleTransitionCheck( ...
                    slotIndex, ...
                    targetPrevState, targetPrevOccupancy, targetPrevAction, targetPrevReward, ...
                    targetNextState, targetNextOccupancy, ...
                    shadowAgent.PendingState, shadowAgent.PendingOccupancy, ...
                    shadowAgent.PendingAction, shadowAgent.PendingReward, ...
                    shadowState, shadowOccupancy);
            end

            %% 6-2. Shadow Transition 완성 / 학습
            shadowAgent.completeTransition();
            [lossShadow, trainingInfoShadow] = shadowAgent.train();

            DebugHelper.printShadowTraining( ...
                slotIndex, shadowAgent, shadowState, shadowOccupancy, ...
                lossShadow, trainingInfoShadow);

            %% 6-3. Target Actual Action을 Shadow에 Oracle 제공
            shadowAgent.observeAction(shadowState, shadowOccupancy, targetAction);
            apjd.ObservedChannel = targetAction;

            %% 6-4. Target / Shadow Q-vector 계산
            dlTargetState = targetAgent.convertStateToDLArray(targetState);
            dlTargetOccupancy = targetAgent.convertOccupancyToDLArray(targetOccupancy);

            qTarget = extractdata(predict( ...
                targetAgent.QNetwork, dlTargetState, dlTargetOccupancy));
            qTarget = double(qTarget(:));

            dlShadowState = shadowAgent.convertStateToDLArray(shadowState);
            dlShadowOccupancy = shadowAgent.convertOccupancyToDLArray(shadowOccupancy);

            qShadow = extractdata(predict( ...
                shadowAgent.QNetwork, dlShadowState, dlShadowOccupancy));
            qShadow = double(qShadow(:));

            [~, greedyTarget] = max(qTarget);
            [~, greedyShadow] = max(qShadow);

            qCosSim = dot(qTarget, qShadow) / ...
                (norm(qTarget) * norm(qShadow) + eps);

            argmaxMatch = double(greedyTarget == greedyShadow);
            qL2Dist = norm(qTarget - qShadow);

            weightDiffNorm = TimeSlotD.computeWeightDiffNorm( ...
                targetAgent.QNetwork, shadowAgent.QNetwork);

            weightNormTarget = TimeSlotD.computeNetworkNorm(targetAgent.QNetwork);
            weightNormShadow = TimeSlotD.computeNetworkNorm(shadowAgent.QNetwork);

            DebugHelper.printTargetVsShadowDQN( ...
                slotIndex, targetAction, qTarget, qShadow, ...
                greedyTarget, greedyShadow, qCosSim, qL2Dist, ...
                weightDiffNorm, weightNormTarget, weightNormShadow);

            %% 6-5. Divergence Log
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

            divergenceLog(end + 1) = entry; %#ok<AGROW>

            %% 7. UT HARQ 수행
            harqResults = cell(1, numel(UTs));
            sinrResults_dB = zeros(1, numel(UTs));
            targetPacketType = [];

            for utIndex = 1:numel(UTs)
                [packetType, SINR_dB] = UTs(utIndex).performHARQ( ...
                    ServiceChannels, ControlChannels, Satellite, apjd);

                harqResults{utIndex} = packetType;
                sinrResults_dB(utIndex) = SINR_dB;

                if utIndex == apjd.TargetUTId
                    targetPacketType = packetType;
                end
            end

            %% 8. Beam Feedback 수신 / Target Reward
            actualACK = false(1, numel(Satellite.Beams));

            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);

                actualACK(beamIndex) = beam.receiveFeedback( ...
                    ControlChannels, Satellite);

                beam.Agent.setReward(actualACK(beamIndex));
            end

            %% 9. Shadow Reward = Oracle
            targetOutcome = actualACK(targetBeamIndex);
            shadowAgent.setReward(targetOutcome);

            DebugHelper.printRewardResult( ...
                slotIndex, targetAction, targetPacketType, targetOutcome, ...
                targetAgent, shadowAgent);

            %% 10. APJ StateManager Update
            %
            % O = APJ RF observation
            % A = Target action Oracle
            % H = Target HARQ Oracle
            %
            % 이 값은 다음 슬롯의 shadowState가 된다.
            if isempty(apjdRFObservation)
                warning("TimeSlotD:EmptyAPJDRFObservation", ...
                    "Slot %d에서 APJ RF observation이 비어 있습니다.", slotIndex);
            else
                apjd.StateManager.update( ...
                    apjdRFObservation, targetAction, targetPacketType);
            end

            %% 11. ACK Log
            if ~isempty(divergenceLog) && divergenceLog(end).slot == slotIndex
                divergenceLog(end).actualACK = double(targetOutcome);
            end

            %% 12. Shadow Prediction 저장
            [predictedAction, predictedQValues] = ...
                shadowAgent.predictAction(shadowState, shadowOccupancy);

            apjd.PredictedChannel = predictedAction;
            apjd.PredictedQValues = predictedQValues;
        end


        function clearChannels(~, ServiceChannels, ControlChannels)
            for channelIndex = 1:numel(ServiceChannels)
                ServiceChannels(channelIndex).clearPacket();
            end

            for channelIndex = 1:numel(ControlChannels)
                ControlChannels(channelIndex).clearPacket();
            end
        end
    end


    methods (Static)

        function normDiff = computeWeightDiffNorm(networkA, networkB)
            learnA = networkA.Learnables;
            learnB = networkB.Learnables;

            if height(learnA) ~= height(learnB)
                error("TimeSlotD:NetworkStructureMismatch", ...
                    "Target과 Shadow Network 구조가 다릅니다.");
            end

            sumSquares = 0;

            for learnableIndex = 1:height(learnA)
                valueA = double(extractdata(learnA.Value{learnableIndex}));
                valueB = double(extractdata(learnB.Value{learnableIndex}));

                if ~isequal(size(valueA), size(valueB))
                    error("TimeSlotD:NetworkParameterSizeMismatch", ...
                        "Target/Shadow parameter size가 다릅니다.");
                end

                difference = valueA(:) - valueB(:);
                sumSquares = sumSquares + sum(difference .^ 2);
            end

            normDiff = sqrt(sumSquares);
        end


        function normValue = computeNetworkNorm(network)
            learnables = network.Learnables;
            sumSquares = 0;

            for learnableIndex = 1:height(learnables)
                value = double(extractdata(learnables.Value{learnableIndex}));
                sumSquares = sumSquares + sum(value(:) .^ 2);
            end

            normValue = sqrt(sumSquares);
        end
    end
end
