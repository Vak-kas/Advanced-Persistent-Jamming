classdef TimeSlotD
    % TimeSlotD
    %
    % ================================================================
    % RF Observation + Oracle Action/Reward Shadow DQN + Attack Phase
    % (Top-K Jamming 지원 버전 / 콘솔 출력 최소화 버전)
    % ================================================================
    %
    % [출력 정책]
    %   - DebugHelper.printTargetVsShadowDQN(...) 딱 하나만 콘솔에 출력.
    %   - 나머지 DebugHelper.print*(...) 호출과 fprintf 블록은 전부
    %     주석 처리(기능은 그대로, 화면 출력만 억제).
    %   - DebugHelper.record*(...)는 print가 아니라 데이터 적재용이라
    %     콘솔에 안 찍히므로 그대로 유지.

    properties
        ReconnaissanceDuration
        TopKJam   % 1 = Top-1만 재밍(기존 동작), 2 = Top-1+Top-2 동시 재밍(기본값)
    end

    methods

        function obj = TimeSlotD(topKJam)
            env;
            obj.ReconnaissanceDuration = reconnaissanceDuration;

            if nargin < 1 || isempty(topKJam)
                topKJam = 2;
            end
            obj.TopKJam = topKJam;
        end


        function [divergenceLog, channelLog] = run(obj, slotIndex, UTs, Satellite, apjd, ...
                ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog)

            %% 1. Time Slot Header
            % DebugHelper.printTimeSlot(slotIndex);

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
                    % DebugHelper.printAgentTraining(beam, lossValue, trainingInfo);
                end

                [selectedChannel, selectionMethod, randomValue, qValues] = ...
                    beam.Agent.selectAction(state, occupancy);

                beam.SelectedChannel = selectedChannel;
                currentSlotOccupancy(selectedChannel) = ...
                    currentSlotOccupancy(selectedChannel) + 1;

                if beamIndex == targetBeamIndex
                    targetState = state;
                    targetOccupancy = occupancy;
                    targetAction = selectedChannel;

                    % DebugHelper.printTargetActionSelection( ...
                    %     slotIndex, beam, selectedChannel, ...
                    %     selectionMethod, randomValue, qValues);

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
                error( ...
                    "TimeSlotD:TargetAgentNotFound", ...
                    "Target Beam %d의 Agent를 찾지 못했습니다.", ...
                    targetBeamIndex);
            end


            %% 4. APJ Attack Decision (Top-K Jamming)
            previousPredictedChannel = apjd.PredictedChannel;
            previousPredictedQValues = apjd.PredictedQValues;

            previousPredictedTop2Channel = [];
            if obj.TopKJam >= 2 && ~isempty(previousPredictedQValues)
                [~, rankedChannels] = sort(previousPredictedQValues(:), 'descend');
                if numel(rankedChannels) >= 2
                    previousPredictedTop2Channel = rankedChannels(2);
                end
            end

            isAttackPhase = slotIndex > obj.ReconnaissanceDuration;
            jammingChannels = [];

            if isAttackPhase

                if ~isempty(previousPredictedChannel)
                    jammingChannels = previousPredictedChannel;

                    if ~isempty(previousPredictedTop2Channel) && ...
                            previousPredictedTop2Channel ~= previousPredictedChannel
                        jammingChannels = [jammingChannels, previousPredictedTop2Channel]; %#ok<AGROW>
                    end

                    apjd.JammingChannel = jammingChannels(1);
                else
                    apjd.JammingChannel = [];
                end

            else
                apjd.JammingChannel = [];
            end

            if ~isempty(previousPredictedChannel)
                DebugHelper.recordAPJPrediction( ...
                    slotIndex, previousPredictedChannel, targetAction, numel(ServiceChannels));
            end

            % fprintf("\n");
            % fprintf("============================================================\n");
            % fprintf("APJ ATTACK STATUS - SLOT %d\n", slotIndex);
            % fprintf("============================================================\n");
            %
            % if isAttackPhase
            %     fprintf("  Phase                   : ATTACK\n");
            %
            %     if isempty(jammingChannels)
            %         fprintf("  Predicted Channel(s)    : NONE\n");
            %         fprintf("  Jamming Channel(s)      : NONE\n");
            %     else
            %         fprintf("  Predicted Channel(s)    : %s\n", mat2str(jammingChannels));
            %         fprintf("  Jamming Channel(s)      : %s\n", mat2str(jammingChannels));
            %         fprintf("  Target Actual Channel   : CH%d\n", targetAction);
            %
            %         if any(jammingChannels == targetAction)
            %             fprintf("  Prediction / Attack Hit : YES\n");
            %         else
            %             fprintf("  Prediction / Attack Hit : NO\n");
            %         end
            %     end
            %
            % else
            %     fprintf("  Phase                   : RECONNAISSANCE\n");
            %     fprintf("  Jamming                 : NONE\n");
            % end
            %
            % fprintf("============================================================\n");


            %% 5. Satellite -> UT Downlink DATA 전송
            dataPackets = cell(1, numel(Satellite.Beams));

            for beamIndex = 1:numel(Satellite.Beams)

                beam = Satellite.Beams(beamIndex);

                dataPackets{beamIndex} = Packet( ...
                    PacketType.DATA, ...
                    NodeType.Satellite, ...
                    Satellite.Id, ...
                    NodeType.UT, ...
                    beam.AssociatedUTId, ...
                    beam.Id, ...
                    ChannelType.Service, ...
                    beam.SelectedChannel);
            end

            for beamIndex = 1:numel(dataPackets)
                packet = dataPackets{beamIndex};
                ServiceChannels(packet.ChannelId).addPacket(packet);
            end


            %% 5.5. APJ 실제 재밍 패킷 주입 (Top-K 채널 전부)
            if isAttackPhase && ~isempty(jammingChannels)

                targetBeamId = Satellite.Beams(targetBeamIndex).Id;

                for jammingChannel = jammingChannels

                    jamPacket = Packet( ...
                        PacketType.JAMMING, ...
                        NodeType.APJ, ...
                        apjd.Id, ...
                        NodeType.UT, ...
                        apjd.TargetUTId, ...
                        targetBeamId, ...
                        ChannelType.Service, ...
                        jammingChannel);

                    ServiceChannels(jammingChannel).addPacket(jamPacket);
                end
            end


            %% 6. Target UT / APJ RF Observation
            targetUT = UTs(apjd.TargetUTId);

            targetUTRFObservation = ...
                targetUT.ObservationManager.observe( ...
                    ServiceChannels, Satellite);

            apjdRFObservation = ...
                apjd.ObservationManager.observe( ...
                    ServiceChannels, Satellite);

            % fprintf("\n");
            % fprintf("============================================================\n");
            % fprintf("RAW RF OBSERVATION VECTOR - SLOT %d\n", slotIndex);
            % fprintf("============================================================\n");
            %
            % fprintf("  UT1 RF Observation       : %s\n", ...
            %     mat2str(double(targetUTRFObservation(:))', 6));
            %
            % fprintf("  APJ RF Observation      : %s\n", ...
            %     mat2str(double(apjdRFObservation(:))', 6));
            %
            % if isAttackPhase && ~isempty(jammingChannels)
            %     fprintf("  APJ Jamming Channel(s)  : %s\n", mat2str(jammingChannels));
            % else
            %     fprintf("  APJ Jamming Channel(s)  : NONE\n");
            % end
            %
            % fprintf("============================================================\n");

            % DebugHelper.printRFObservationComparison( ...
            %     slotIndex, ...
            %     targetUT, ...
            %     apjd, ...
            %     targetUTRFObservation, ...
            %     apjdRFObservation);


            %% 7. APJ Shadow Agent
            shadowAgent = apjd.Agent;

            shadowState = apjd.StateManager.getState();

            shadowOccupancy = targetOccupancy;

            shadowAgent.setCurrentState(shadowState);
            shadowAgent.setCurrentOccupancy(shadowOccupancy);


            %% 7-1. RF State / Oracle component 비교
            % if ~isempty(targetPrevState) && ...
            %    ~isempty(shadowAgent.PendingState)
            %
            %     DebugHelper.printRFOracleTransitionCheck( ...
            %         slotIndex, ...
            %         targetPrevState, ...
            %         targetPrevOccupancy, ...
            %         targetPrevAction, ...
            %         targetPrevReward, ...
            %         targetNextState, ...
            %         targetNextOccupancy, ...
            %         shadowAgent.PendingState, ...
            %         shadowAgent.PendingOccupancy, ...
            %         shadowAgent.PendingAction, ...
            %         shadowAgent.PendingReward, ...
            %         shadowState, ...
            %         shadowOccupancy);
            % end


            %% 7-2. Shadow 이전 Transition 완성
            shadowAgent.completeTransition();


            %% 7-3. Shadow DQN 학습
            [lossShadow, trainingInfoShadow] = ...
                shadowAgent.train();

            % DebugHelper.printShadowTraining( ...
            %     slotIndex, ...
            %     shadowAgent, ...
            %     shadowState, ...
            %     shadowOccupancy, ...
            %     lossShadow, ...
            %     trainingInfoShadow);


            %% 7-4. Target Actual Action Oracle 제공
            shadowAgent.observeAction( ...
                shadowState, ...
                shadowOccupancy, ...
                targetAction);

            apjd.ObservedChannel = targetAction;


            %% 7-5. Target / Shadow Q-vector 계산
            dlTargetState = ...
                targetAgent.convertStateToDLArray(targetState);

            dlTargetOccupancy = ...
                targetAgent.convertOccupancyToDLArray(targetOccupancy);

            qTarget = extractdata( ...
                predict( ...
                    targetAgent.QNetwork, ...
                    dlTargetState, ...
                    dlTargetOccupancy));

            qTarget = double(qTarget(:));


            dlShadowState = ...
                shadowAgent.convertStateToDLArray(shadowState);

            dlShadowOccupancy = ...
                shadowAgent.convertOccupancyToDLArray(shadowOccupancy);

            qShadow = extractdata( ...
                predict( ...
                    shadowAgent.QNetwork, ...
                    dlShadowState, ...
                    dlShadowOccupancy));

            qShadow = double(qShadow(:));


            [~, greedyTarget] = max(qTarget);
            [~, greedyShadow] = max(qShadow);

            qCosSim = dot(qTarget, qShadow) / ...
                (norm(qTarget) * norm(qShadow) + eps);

            argmaxMatch = ...
                double(greedyTarget == greedyShadow);

            qL2Dist = ...
                norm(qTarget - qShadow);

            weightDiffNorm = ...
                TimeSlotD.computeWeightDiffNorm( ...
                    targetAgent.QNetwork, ...
                    shadowAgent.QNetwork);

            weightNormTarget = ...
                TimeSlotD.computeNetworkNorm( ...
                    targetAgent.QNetwork);

            weightNormShadow = ...
                TimeSlotD.computeNetworkNorm( ...
                    shadowAgent.QNetwork);

            % ---- 유일하게 콘솔에 남기는 출력 ----
            DebugHelper.printTargetVsShadowDQN( ...
                slotIndex, ...
                targetAction, ...
                qTarget, ...
                qShadow, ...
                greedyTarget, ...
                greedyShadow, ...
                qCosSim, ...
                qL2Dist, ...
                weightDiffNorm, ...
                weightNormTarget, ...
                weightNormShadow);


            %% 7-6. Divergence Log
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

            entry.isAttackPhase = isAttackPhase;
            entry.jammingChannels = jammingChannels;

            divergenceLog(end + 1) = entry; %#ok<AGROW>


            %% 8. UT HARQ 수행
            harqResults = cell(1, numel(UTs));
            sinrResults_dB = zeros(1, numel(UTs));
            targetPacketType = [];
            targetSINR_dB = [];

            for utIndex = 1:numel(UTs)

                [packetType, SINR_dB] = ...
                    UTs(utIndex).performHARQ( ...
                        ServiceChannels, ...
                        ControlChannels, ...
                        Satellite, ...
                        apjd);

                harqResults{utIndex} = packetType;
                sinrResults_dB(utIndex) = SINR_dB;

                if utIndex == apjd.TargetUTId
                    targetPacketType = packetType;
                    targetSINR_dB = SINR_dB;
                end
            end


            %% 9. Beam Feedback 수신 / Target Reward
            actualACK = ...
                false(1, numel(Satellite.Beams));

            for beamIndex = 1:numel(Satellite.Beams)

                beam = Satellite.Beams(beamIndex);

                actualACK(beamIndex) = ...
                    beam.receiveFeedback( ...
                        ControlChannels, ...
                        Satellite);

                beam.Agent.setReward( ...
                    actualACK(beamIndex));
            end


            %% 10. Shadow Reward = Oracle
            targetOutcome = ...
                actualACK(targetBeamIndex);

            shadowAgent.setReward( ...
                targetOutcome);

            % DebugHelper.printRewardResult( ...
            %     slotIndex, ...
            %     targetAction, ...
            %     targetPacketType, ...
            %     targetOutcome, ...
            %     targetAgent, ...
            %     shadowAgent);

            DebugHelper.recordTargetUTOutcome( ...
                slotIndex, targetPacketType, targetSINR_dB, obj.ReconnaissanceDuration);


            %% 11. APJ StateManager Update
            if isempty(apjdRFObservation)

                warning( ...
                    "TimeSlotD:EmptyAPJDRFObservation", ...
                    "Slot %d에서 APJ RF observation이 비어 있습니다.", ...
                    slotIndex);

            else

                apjd.StateManager.update( ...
                    apjdRFObservation, ...
                    targetAction, ...
                    targetPacketType);
            end


            %% 12. ACK Log
            if ~isempty(divergenceLog) && ...
               divergenceLog(end).slot == slotIndex

                divergenceLog(end).actualACK = ...
                    double(targetOutcome);
            end


            %% 13. NEXT-SLOT Shadow Prediction
            nextShadowState = ...
                apjd.StateManager.getState();

            predictionOccupancy = ...
                targetOccupancy;

            [predictedAction, predictedQValues] = ...
                shadowAgent.predictAction( ...
                    nextShadowState, ...
                    predictionOccupancy);

            apjd.PredictedChannel = ...
                predictedAction;

            apjd.PredictedQValues = ...
                predictedQValues;

            % fprintf("\n");
            % fprintf("============================================================\n");
            % fprintf("APJ NEXT-SLOT PREDICTION - SLOT %d\n", slotIndex);
            % fprintf("============================================================\n");
            %
            % fprintf("  Current Phase           : %s\n", ...
            %     TimeSlotD.phaseToString(isAttackPhase));
            %
            % fprintf("  Prediction Target Slot  : %d\n", ...
            %     slotIndex + 1);
            %
            % fprintf("  Predicted Channel (Top-1) : CH%d\n", ...
            %     predictedAction);
            %
            % fprintf("============================================================\n");
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
                error( ...
                    "TimeSlotD:NetworkStructureMismatch", ...
                    "Target과 Shadow Network 구조가 다릅니다.");
            end

            sumSquares = 0;

            for learnableIndex = 1:height(learnA)

                valueA = ...
                    double( ...
                        extractdata( ...
                            learnA.Value{learnableIndex}));

                valueB = ...
                    double( ...
                        extractdata( ...
                            learnB.Value{learnableIndex}));

                if ~isequal(size(valueA), size(valueB))
                    error( ...
                        "TimeSlotD:NetworkParameterSizeMismatch", ...
                        "Target/Shadow parameter size가 다릅니다.");
                end

                difference = ...
                    valueA(:) - valueB(:);

                sumSquares = ...
                    sumSquares + sum(difference .^ 2);
            end

            normDiff = ...
                sqrt(sumSquares);
        end


        function normValue = computeNetworkNorm(network)

            learnables = ...
                network.Learnables;

            sumSquares = 0;

            for learnableIndex = 1:height(learnables)

                value = ...
                    double( ...
                        extractdata( ...
                            learnables.Value{learnableIndex}));

                sumSquares = ...
                    sumSquares + ...
                    sum(value(:) .^ 2);
            end

            normValue = ...
                sqrt(sumSquares);
        end


        function text = phaseToString(isAttackPhase)

            if isAttackPhase
                text = "ATTACK";
            else
                text = "RECONNAISSANCE";
            end
        end

    end

end