classdef TimeSlotB
    % TimeSlotB  (GA-Dueling DQN, 독립 학습 — 원 논문 충실 재현)
    %
    % ================================================================
    % Benchmark: 원 논문(Xia et al., Sensors 2024, GA-Dueling DQN)의
    % 학습 방식을 그대로 재현. Target 정책을 섀도잉(clone)하지 않고,
    % 재머가 "자기 스스로" 매 슬롯 재밍 채널을 epsilon-greedy로 선택하고,
    % 그 선택이 Target을 실제로 막았는지(공격 성공/실패)를 스스로
    % 관측해서 자기 reward로 학습하는 완전히 독립적인 RL 루프.
    % ================================================================
    %
    % TimeSlotB(섀도잉 버전)와의 구조적 차이:
    %   - Action  : shadowAgent.observeAction(...)으로 Target 실제
    %     action을 주입받는 게 아니라, shadowAgent.selectAction(...)으로
    %     "자기가" epsilon-greedy로 고른다 (Beam Agent와 완전히 동일한
    %     방식).
    %   - Reward  : "Shadow가 Target 정책을 얼마나 잘 흉내냈는가"가
    %     아니라, "자기가 선택한 채널이 실제로 Target을 NACK 시켰는가"
    %     (자기 자신의 공격 성공 여부)를 SINR 추정(estimateTargetSINR/
    %     generatePseudoHARQ, 기존 로직 재사용)으로 판정해서 reward로 씀.
    %   - 학습 루프: completeTransition -> train -> selectAction 순서로,
    %     Beam Agent의 루프(섹션 3)와 완전히 동일한 패턴을 따른다.
    %
    % Occupancy는 기존 프로젝트 전제(Oracle)를 그대로 유지한다.
    %
    % Jamming budget: 원 논문은 매 슬롯 "채널 1개"를 선택하는 구조이므로
    % 이 파일도 기본은 1채널이다. 우리 APJ(TopKJam=2)와 "동일 2채널
    % budget"으로 공정 비교하려면 아래 5.4절 주석 참고(Top-2 epsilon-greedy
    % 확장 지점 — 필요시 요청해서 추가).
    %
    % [출력 정책] 콘솔 출력 최소화 — 슬롯별 채널/보상 요약 한 줄만.

    properties
        ReconnaissanceDuration
    end

    methods

        function obj = TimeSlotB()
            env;
            obj.ReconnaissanceDuration = reconnaissanceDuration;
        end


        function [gLog, channelLog] = run(obj, slotIndex, UTs, Satellite, apjd, ...
                ServiceChannels, ControlChannels, targetBeamIndex, gLog, channelLog)

            %% 1. Time Slot Header
            % DebugHelper.printTimeSlot(slotIndex);

            %% 2. Channel 초기화
            obj.clearChannels(ServiceChannels, ControlChannels);

            %% 3. Satellite Beam Action Selection (Target — 기존과 동일, 변경 없음)
            currentSlotOccupancy = zeros(1, numel(ServiceChannels));

            targetBeam = [];
            targetAgent = [];
            targetOccupancy = [];
            targetAction = [];

            for beamIndex = 1:numel(Satellite.Beams)

                beam = Satellite.Beams(beamIndex);

                state = beam.StateManager.getState();

                beam.StateManager.setCurrentOccupancy(currentSlotOccupancy);
                occupancy = beam.StateManager.getCurrentOccupancy();

                if beamIndex == targetBeamIndex
                    targetBeam = beam;
                    targetAgent = beam.Agent;
                end

                beam.Agent.setCurrentState(state);
                beam.Agent.setCurrentOccupancy(occupancy);
                beam.Agent.completeTransition();

                beam.Agent.train();

                [selectedChannel, selectionMethod, randomValue, qValues] = ...
                    beam.Agent.selectAction(state, occupancy);

                beam.SelectedChannel = selectedChannel;
                currentSlotOccupancy(selectedChannel) = ...
                    currentSlotOccupancy(selectedChannel) + 1;

                if beamIndex == targetBeamIndex
                    targetOccupancy = occupancy;
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

            if isempty(targetAgent)
                error("TimeSlotB:TargetAgentNotFound", ...
                    "Target Beam %d의 Agent를 찾지 못했습니다.", targetBeamIndex);
            end

            isAttackPhase = slotIndex > obj.ReconnaissanceDuration;


            %% 4. [핵심] Independent Jammer: 자기 스스로 채널 선택 (Beam과 동일한 루프)
            %
            % 정찰 구간에는 이 에이전트가 "행동할 이유(잼밍 시도)" 자체가
            % 없으므로 — 원 논문에도 정찰이라는 개념이 없음 — attack phase
            % 에만 select/train 루프를 돌린다. 이건 섀도잉 버전과 달리
            % "정찰 중엔 학습 안 하는 게 부당한 비교"가 아니라, 독립 RL의
            % 자연스러운 성질이다(행동 없이는 보상도, 학습할 것도 없음).
            selectedJamChannel = [];
            jamSelectionMethod = "NONE";
            jamRandomValue = NaN;
            jamQValues = [];

            if isAttackPhase

                jammerState = apjd.StateManager.getState();
                jammerOccupancy = targetOccupancy;   % Oracle occupancy, 기존 전제 유지

                apjd.Agent.setCurrentState(jammerState);
                apjd.Agent.setCurrentOccupancy(jammerOccupancy);
                apjd.Agent.completeTransition();   % 직전 슬롯 transition 완성(직전에 매긴 reward 사용)

                [lossShadow, trainingInfoShadow] = apjd.Agent.train(); %#ok<ASGLU>

                [selectedJamChannel, jamSelectionMethod, jamRandomValue, jamQValues] = ...
                    apjd.Agent.selectAction(jammerState, jammerOccupancy);

                apjd.JammingChannel = selectedJamChannel;
            else
                apjd.JammingChannel = [];
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


            %% 5.5. 재머 자기 선택 채널에 실제 재밍 패킷 주입
            %
            % [확장 지점] 우리 APJ(TopKJam=2)와 동일 jamming budget으로
            % 맞추려면, selectedJamChannel(Top-1) 외에 Top-2 채널도
            % epsilon-greedy로 뽑아서 여기서 같이 주입하면 됨. 지금은
            % 원 논문(단일 채널 선택)에 충실하게 1채널만 재밍.
            if isAttackPhase && ~isempty(selectedJamChannel)
                targetBeamId = Satellite.Beams(targetBeamIndex).Id;
                jamPacket = Packet(PacketType.JAMMING, NodeType.APJ, apjd.Id, ...
                    NodeType.UT, apjd.TargetUTId, targetBeamId, ...
                    ChannelType.Service, selectedJamChannel);
                ServiceChannels(selectedJamChannel).addPacket(jamPacket);
            end


            %% 6. Target UT / APJ RF Observation
            targetUT = UTs(apjd.TargetUTId);
            targetUT.ObservationManager.observe(ServiceChannels, Satellite);
            apjdRFObservation = apjd.ObservationManager.observe(ServiceChannels, Satellite);


            %% 6.5. UT HARQ 수행 (실제 결과)
            targetPacketType = [];
            targetSINR_dB = [];
            for utIndex = 1:numel(UTs)
                [packetType, SINR_dB] = UTs(utIndex).performHARQ( ...
                    ServiceChannels, ControlChannels, Satellite, apjd);
                if utIndex == apjd.TargetUTId
                    targetPacketType = packetType;
                    targetSINR_dB = SINR_dB;
                end
            end


            %% 7. Beam Feedback / Target Reward (Target은 항상 실제 결과로 학습, 변경 없음)
            actualACK = false(1, numel(Satellite.Beams));
            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);
                actualACK(beamIndex) = beam.receiveFeedback(ControlChannels, Satellite);
                beam.Agent.setReward(actualACK(beamIndex));
            end
            targetOutcome = actualACK(targetBeamIndex);

            DebugHelper.recordTargetUTOutcome( ...
                slotIndex, targetPacketType, targetSINR_dB, obj.ReconnaissanceDuration);


            %% 8. [핵심] Independent Jammer 자기 Reward — "자기 공격이 성공했는가"
            %
            % Oracle이 아니라, APJD가 자기 위치 기준 SINR 추정(기존
            % estimateTargetSINR/generatePseudoHARQ 로직 그대로 재사용)으로
            % "Target이 이번 슬롯 성공했을지"를 판정한 뒤, 그 반대(=Target
            % 실패 = 자기 공격 성공)를 자기 reward로 삼는다. 이때
            % estimateTargetSINR은 ServiceChannels에 이미 들어있는
            % JAMMING 패킷(자기가 실제로 쏜 것)을 그대로 반영하므로,
            % "선택한 채널이 Target 채널과 실제로 겹쳤는지"가 정확히
            % SINR 저하로 반영된다.
            estimatedOutcome = NaN;
            attackerSuccess = false;

            if isAttackPhase

                estimatedSINR_dB = apjd.estimateTargetSINR(ServiceChannels, Satellite, targetUT);
                estimatedPacketType = apjd.generatePseudoHARQ(estimatedSINR_dB);

                if ~isempty(estimatedPacketType)
                    estimatedOutcome = double(estimatedPacketType == PacketType.ACK);
                    attackerSuccess = (estimatedPacketType == PacketType.NACK);   % Target 실패 = 공격 성공
                end

                % apjRewardFunction(x) = x*apjSuccessReward + (~x)*apjFailureReward
                % 원래는 "Target 성공(ACK) 예측"을 위한 식이었지만, 여기서는
                % attackerSuccess(자기 공격 성공 여부)를 그대로 넣어서
                % "공격 성공 시 +apjSuccessReward, 실패 시 apjFailureReward"로
                % 재해석해서 사용한다.
                env;
                rewardValue = apjRewardFunction(attackerSuccess);

                apjd.Agent.setReward(rewardValue);

                fprintf("  [TimeSlotB] Slot %d: Jammer selected CH%d (%s) -> Target actual CH%d, %s -> AttackerSuccess=%d, Reward=%.2f\n", ...
                    slotIndex, selectedJamChannel, jamSelectionMethod, targetAction, ...
                    string(targetPacketType), attackerSuccess, rewardValue);

                apjd.StateManager.update(apjdRFObservation, selectedJamChannel, targetPacketType);
            else
                % 정찰 구간: 상태 이력만 쌓아둠(선택 사항) — 재밍/보상 없음.
                apjd.StateManager.update(apjdRFObservation, targetAction, targetPacketType);
            end


            %% 9. Log 기록
            entry.slot = slotIndex;
            entry.isAttackPhase = isAttackPhase;
            entry.observedChannel = targetAction;      % Target 실제 채널
            entry.jammingChannel = selectedJamChannel;  % 재머 자기 선택 채널
            entry.actualACK = double(targetOutcome);
            entry.estimatedOutcome = estimatedOutcome;
            entry.attackerSuccess = double(attackerSuccess);

            gLog(end + 1) = entry; %#ok<AGROW>

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