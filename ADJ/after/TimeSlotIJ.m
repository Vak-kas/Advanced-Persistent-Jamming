classdef TimeSlotIJ
    properties
        ReconnaissanceDuration
        EnableJamming = true
        DryRun = false
        Verbose = false  % false로 두면 매 슬롯 디버그 출력을 생략 (배치 실험용)
    end

    methods
        %% ============================================================
        function obj = TimeSlotIJ(reconnaissanceDuration)
            if nargin < 1 || isempty(reconnaissanceDuration)
                error( ...
                    "TimeSlotIJ:MissingReconnaissanceDuration", ...
                    "reconnaissanceDuration을 생성자에 전달해야 합니다.");
            end
            obj.ReconnaissanceDuration = reconnaissanceDuration;
        end

        %% ============================================================
        function [ijLog, channelLog] = run( ...
                obj, slotIndex, UTs, Satellite, ij, ...
                ServiceChannels, ControlChannels, targetBeamIndex, ...
                ijLog, channelLog)

            %% 0. Time Slot Header
            if obj.Verbose
                DebugHelper.printTimeSlot(slotIndex);
            end

            %% 1. Channel 초기화
            obj.clearChannels(ServiceChannels, ControlChannels);

            %% 2. Satellite Beam Action Selection
            currentSlotOccupancy = zeros(1, numel(ServiceChannels));
            targetAction = [];
            targetBeam = [];

            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);

                state = beam.StateManager.getState();
                beam.StateManager.setCurrentOccupancy(currentSlotOccupancy);
                occupancy = beam.StateManager.getCurrentOccupancy();

                beam.Agent.setCurrentState(state);
                beam.Agent.setCurrentOccupancy(occupancy);
                beam.Agent.completeTransition();
                beam.Agent.train();

                [selectedChannel, selectionMethod, ~, qValues] = ...
                    beam.Agent.selectAction(state, occupancy);

                beam.SelectedChannel = selectedChannel;
                currentSlotOccupancy(selectedChannel) = currentSlotOccupancy(selectedChannel) + 1;

                if beamIndex == targetBeamIndex
                    targetBeam = beam;
                    targetAction = selectedChannel;

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

            %% 3. Phase 판정
            isAttackPhase = slotIndex > obj.ReconnaissanceDuration;
            shouldRunIJPipeline = isAttackPhase || obj.DryRun;

            selectedChannelsFromPrevSlot = ij.JammingChannels;

            if isAttackPhase && obj.EnableJamming && ~isempty(selectedChannelsFromPrevSlot)
                jammedChannelsThisSlot = selectedChannelsFromPrevSlot;

                for channelIndex = jammedChannelsThisSlot
                    jamPacket = Packet( ...
                        PacketType.JAMMING, NodeType.IJ, ij.Id, ...
                        NodeType.UT, ij.TargetUTId, targetBeam.Id, ...
                        ChannelType.Service, channelIndex);

                    ServiceChannels(channelIndex).addPacket(jamPacket);
                end
            else
                jammedChannelsThisSlot = [];
            end

            %% 4. Satellite -> UT Downlink DATA
            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);

                packet = Packet( ...
                    PacketType.DATA, NodeType.Satellite, Satellite.Id, ...
                    NodeType.UT, beam.AssociatedUTId, beam.Id, ...
                    ChannelType.Service, beam.SelectedChannel);

                ServiceChannels(packet.ChannelId).addPacket(packet);
            end

            %% 5~8. IJ Sensing / Reward(SINR 추정) / Train / Next Action
            if shouldRunIJPipeline

                newState = ij.senseState(ServiceChannels, Satellite);
                dummyOccupancy = zeros(1, numel(ServiceChannels));

                targetUT = UTs(ij.TargetUTId);

                [~, estimatedOutcome] = ij.estimateAttackOutcome( ...
                    ServiceChannels, Satellite, targetUT, selectedChannelsFromPrevSlot);

                if isempty(estimatedOutcome)
                    attackSucceeded = false;
                else
                    attackSucceeded = (estimatedOutcome == PacketType.NACK);
                end

                ij.Agent.setReward(attackSucceeded);
                rewardValueIJ = ij.Agent.RewardHistory(end);

                ij.Agent.setCurrentState(newState);
                ij.Agent.setCurrentOccupancy(dummyOccupancy);
                ij.Agent.completeTransition();
                [lossIJ, trainingInfoIJ] = ij.Agent.train();

                if obj.Verbose
                    DebugHelper.printIJTraining(ij, lossIJ, trainingInfoIJ);
                end

                [actionIndex, selectionMethodIJ, ~, qValuesIJ] = ...
                    ij.Agent.selectAction(newState, dummyOccupancy);

                ij.JammingChannels = ij.Agent.decodeAction(actionIndex);

                if obj.Verbose
                    DebugHelper.printIJActionSelection( ...
                        slotIndex, ij, actionIndex, selectionMethodIJ, qValuesIJ, rewardValueIJ);
                end

            else
                lossIJ = NaN;
                rewardValueIJ = NaN;
                selectionMethodIJ = "inactive";
                qValuesIJ = [];
            end

            %% 9. UT HARQ
            targetPacketType = [];
            targetSINR_dB = [];

            for utIndex = 1:numel(UTs)
                [packetType, SINR_dB] = UTs(utIndex).performHARQ( ...
                    ServiceChannels, ControlChannels, Satellite, ij);

                if utIndex == ij.TargetUTId
                    targetPacketType = packetType;
                    targetSINR_dB = SINR_dB;
                end
            end

            %% 10. Beam Feedback / Reward
            actualACK = false(1, numel(Satellite.Beams));

            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);
                actualACK(beamIndex) = beam.receiveFeedback(ControlChannels, Satellite);
                beam.Agent.setReward(actualACK(beamIndex));
            end

            %% 11. 로그 기록
            entry.slot = slotIndex;
            entry.isAttackPhase = isAttackPhase;
            entry.dryRunActive = obj.DryRun && ~isAttackPhase;
            entry.lossIJ = lossIJ;
            entry.jammedChannels = jammedChannelsThisSlot;
            entry.selectedChannels = selectedChannelsFromPrevSlot;
            entry.nextJamChannels = ij.JammingChannels;
            entry.targetChannel = targetAction;
            entry.targetHit = isAttackPhase && ~isempty(jammedChannelsThisSlot) && ...
                any(jammedChannelsThisSlot == targetAction);
            entry.targetACK = double(actualACK(targetBeamIndex));
            entry.targetSINR_dB = targetSINR_dB;
            entry.rewardIJ = rewardValueIJ;
            entry.epsilonIJ = ij.Agent.Epsilon;
            entry.selectionMethod = selectionMethodIJ;

            if isempty(qValuesIJ)
                entry.qValuesIJ = NaN(1, ij.Agent.NumActions);
            else
                entry.qValuesIJ = qValuesIJ(:)';
            end

            ijLog(end + 1) = entry; %#ok<AGROW>

            DebugHelper.recordTargetUTOutcome(slotIndex, targetPacketType, targetSINR_dB, obj.ReconnaissanceDuration);
        end

        %% ============================================================
        function clearChannels(~, ServiceChannels, ControlChannels)
            for channelIndex = 1:numel(ServiceChannels)
                ServiceChannels(channelIndex).clearPacket();
            end
            for channelIndex = 1:numel(ControlChannels)
                ControlChannels(channelIndex).clearPacket();
            end
        end
    end
end