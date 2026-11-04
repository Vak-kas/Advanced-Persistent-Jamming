classdef TimeSlotC
    % TimeSlotC
    %
    % ================================================================
    % Baseline: Fixed-Channel Comb Jammer
    % ================================================================
    %
    % - 학습/예측 없음. Shadow DQN도, 순환(sweep)도 없음.
    % - 정찰 기간(ReconnaissanceDuration) 동안은 재밍 없음.
    % - 공격 기간에는 FixedChannels(예: [3 5])에 지정된 채널만
    %   처음부터 끝까지 고정으로 계속 재밍한다 (TimeSlotS처럼 채널을
    %   순환하지 않음).
    % - Target Beam은 원본 TimeSlot.m과 동일하게 정상적으로 학습/행동한다.
    % - Jamming Hit Rate 계산을 위해 (slot, selectedChannel,
    %   jammingChannels, isAttackPhase)를 combLog로 반환한다.

    properties
        Verbose = false   % true: per-slot console output (debugging only)
        ReconnaissanceDuration
        FixedChannels   % 항상 재밍할 채널 목록, 예: [3 5]
    end

    methods

        function obj = TimeSlotC(fixedChannels)
            env;
            obj.ReconnaissanceDuration = reconnaissanceDuration;

            if nargin < 1 || isempty(fixedChannels)
                fixedChannels = [3 5];   % 기본값
            end
            obj.FixedChannels = fixedChannels;
        end


        function combLog = run(obj, slotIndex, UTs, Satellite, apj, ServiceChannels, ControlChannels, targetBeamIndex, combLog)

            %% 1. Time Slot Header
            if obj.Verbose, DebugHelper.printTimeSlot(slotIndex); end

            %% 2. Channel 초기화
            obj.clearChannels(ServiceChannels, ControlChannels);

            %% 3. Satellite Beam Action Selection (원본 TimeSlot.m과 동일)
            currentSlotOccupancy = zeros(1, numel(ServiceChannels));
            targetSelectedChannel = [];

            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);

                state = beam.StateManager.getState();
                beam.StateManager.setCurrentOccupancy(currentSlotOccupancy);
                occupancy = beam.StateManager.getCurrentOccupancy();

                beam.Agent.setCurrentState(state);
                beam.Agent.setCurrentOccupancy(occupancy);
                beam.Agent.completeTransition();

                [lossValue, trainingInfo] = beam.Agent.train();
                if obj.Verbose && beamIndex == targetBeamIndex
                    DebugHelper.printAgentTraining(beam, lossValue, trainingInfo);
                end

                [selectedChannel, selectionMethod, randomValue, qValues] = beam.Agent.selectAction(state, occupancy);

                beam.SelectedChannel = selectedChannel;
                currentSlotOccupancy(selectedChannel) = currentSlotOccupancy(selectedChannel) + 1;

                if beamIndex == targetBeamIndex
                    targetSelectedChannel = selectedChannel;
                    if obj.Verbose
                        DebugHelper.printTargetActionSelection( ...
                            slotIndex, beam, selectedChannel, selectionMethod, randomValue, qValues);
                    end
                end
            end

            %% 4. Fixed-Channel Comb Jammer 공격 결정
            isAttackPhase = slotIndex > obj.ReconnaissanceDuration;
            jammingChannels = [];

            if isAttackPhase
                jammingChannels = obj.FixedChannels;
            end

            if obj.Verbose
                fprintf("\n============================================================\n");
                fprintf("FIXED COMB JAMMER STATUS - SLOT %d\n", slotIndex);
                fprintf("============================================================\n");
                if isAttackPhase
                    fprintf("  Phase              : ATTACK\n");
                    fprintf("  Jamming Channels   : %s (고정)\n", mat2str(jammingChannels));
                else
                    fprintf("  Phase              : RECONNAISSANCE\n");
                    fprintf("  Jamming            : NONE\n");
                end
                fprintf("============================================================\n");
            end

            %% 5. Satellite -> UT Downlink DATA 전송
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

            %% 5.5. 고정 채널 재밍 패킷 주입
            if isAttackPhase && ~isempty(jammingChannels)
                targetBeamId = Satellite.Beams(targetBeamIndex).Id;
                for jc = jammingChannels
                    jamPacket = Packet(PacketType.JAMMING, NodeType.APJ, apj.Id, ...
                        NodeType.UT, apj.TargetUTId, targetBeamId, ChannelType.Service, jc);
                    ServiceChannels(jc).addPacket(jamPacket);
                end
            end

            %% 6. UT HARQ 수행
            targetPacketType = [];
            targetSINR_dB = [];
            for utIndex = 1:numel(UTs)
                [packetType, SINR_dB] = UTs(utIndex).performHARQ(ServiceChannels, ControlChannels, Satellite, apj);
                if utIndex == apj.TargetUTId
                    targetPacketType = packetType;
                    targetSINR_dB = SINR_dB;
                end
            end

            %% 7. Beam Feedback 수신 / Reward
            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);
                isACK = beam.receiveFeedback(ControlChannels, Satellite);
                beam.Agent.setReward(isACK);
            end

            %% 8. Target UT ACK/SINR 기록
            DebugHelper.recordTargetUTOutcome(slotIndex, targetPacketType, targetSINR_dB, obj.ReconnaissanceDuration);

            %% 9. Comb Log 기록 (Jamming Hit Rate 계산용)
            entry.slot = slotIndex;
            entry.observedChannel = targetSelectedChannel;
            entry.jammingChannels = jammingChannels;
            entry.isAttackPhase = isAttackPhase;
            combLog(end + 1) = entry; %#ok<AGROW>
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
end