classdef TimeSlotS
    % TimeSlotS
    %
    % ================================================================
    % Baseline: Simple Sweep(Comb) Jammer
    % ================================================================
    %
    % - 학습/예측 없음. Shadow DQN 자체가 없다.
    % - 정찰 기간(ReconnaissanceDuration) 동안은 재밍 없음.
    % - 공격 기간에는 채널 쌍을 (1,2) -> (3,4) -> (5,6) -> (7,8) -> (9,10)
    %   순서로 DwellSlots 슬롯마다 다음 쌍으로 넘어가며 매 슬롯 2개 채널을
    %   동시에 재밍한다 (한 바퀴 돌면 다시 (1,2)부터 반복).
    % - Target Beam은 원본 TimeSlot.m과 동일하게 정상적으로 학습/행동한다.
    % - Target UT의 ACK/SINR을 DebugHelper.recordTargetUTOutcome으로 기록해서
    %   FigureHelper.plotTargetUTThroughput를 그대로 재사용할 수 있게 한다.
    %
    % [추가됨] mainD.m/mainDE.m과 동일하게 Jamming Hit Rate를 계산할 수
    % 있도록, 매 슬롯 (slot, selectedChannel, jammingChannels, isAttackPhase)를
    % sweepLog에 기록해서 반환한다.

    properties
        Verbose = false   % true: per-slot console output (debugging only)
        ReconnaissanceDuration
        DwellSlots
        ChannelPairs   % N x 2, 각 행이 동시에 재밍할 채널 쌍
    end

    methods

        function obj = TimeSlotS(numChannels, dwellSlots)
            env;
            obj.ReconnaissanceDuration = reconnaissanceDuration;

            if nargin < 2 || isempty(dwellSlots)
                dwellSlots = 1;     % 채널 쌍 하나당 재밍 유지 슬롯 수 (기본값, 논문 설정)
            end
            obj.DwellSlots = dwellSlots;

            if nargin < 1 || isempty(numChannels)
                numChannels = evalin('caller', 'numChannels'); %#ok<NASGU>
            end

            pairStarts = 1:2:numChannels;
            numPairs = numel(pairStarts);
            pairs = zeros(numPairs, 2);
            for p = 1:numPairs
                ch1 = pairStarts(p);
                ch2 = min(ch1 + 1, numChannels);   % numChannels 홀수면 마지막 쌍은 채널 1개만
                pairs(p, :) = [ch1, ch2];
            end
            obj.ChannelPairs = pairs;
        end


        function sweepLog = run(obj, slotIndex, UTs, Satellite, apj, ServiceChannels, ControlChannels, targetBeamIndex, sweepLog)

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

            %% 4. Sweep Jammer 공격 결정
            isAttackPhase = slotIndex > obj.ReconnaissanceDuration;
            jammingChannels = [];

            if isAttackPhase
                elapsedAttackSlots = slotIndex - obj.ReconnaissanceDuration - 1;  % 0-based
                numPairs = size(obj.ChannelPairs, 1);
                pairIndex = mod(floor(elapsedAttackSlots / obj.DwellSlots), numPairs) + 1;
                jammingChannels = unique(obj.ChannelPairs(pairIndex, :));
            end

            if obj.Verbose
                fprintf("\n============================================================\n");
                fprintf("SWEEP JAMMER STATUS - SLOT %d\n", slotIndex);
                fprintf("============================================================\n");
                if isAttackPhase
                    fprintf("  Phase              : ATTACK\n");
                    fprintf("  Jamming Channels   : %s\n", mat2str(jammingChannels));
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

            %% 5.5. Sweep Jammer 실제 재밍 패킷 주입 (채널 쌍 동시)
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

            %% 8. Target UT ACK/SINR 기록 (FigureHelper.plotTargetUTThroughput용)
            DebugHelper.recordTargetUTOutcome(slotIndex, targetPacketType, targetSINR_dB, obj.ReconnaissanceDuration);

            %% 9. [추가됨] Sweep Log 기록 (Jamming Hit Rate 계산용)
            entry.slot = slotIndex;
            entry.observedChannel = targetSelectedChannel;
            entry.jammingChannels = jammingChannels;
            entry.isAttackPhase = isAttackPhase;
            sweepLog(end + 1) = entry; %#ok<AGROW>
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