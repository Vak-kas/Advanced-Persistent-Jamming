classdef TimeSlotP
    % TimeSlotP  (non-learning Predictor baseline: recency + frequency)
    %
    % ================================================================
    % Target 의 관측된 채널 선택 이력만으로 다음 채널을 "통계적으로" 예측하는
    % 비학습 재머. (리뷰어 요청: "APJ 의 이득이 단순 채널 반복 통계로
    % 설명되지 않는가?" 를 확인하기 위한 baseline)
    %
    %   재밍 채널 (B_J = 2):
    %     1) Target 이 직전 슬롯(t-1)에 사용한 채널            (recency)
    %     2) 최근 HistoryWindow 슬롯 동안 가장 자주 사용한 채널 (frequency)
    %        - 1)과 같으면 두 번째로 자주 사용한 채널
    %
    %   정찰 구간(slot <= ReconnaissanceDuration): 관측만, 재밍 없음
    %   공격 구간(slot >  ReconnaissanceDuration): 위 규칙으로 재밍
    %
    %   재밍 결정은 슬롯 t 의 Target 행동이 나오기 "전" 에, t-1 까지의 이력으로만
    %   내린다 (APJ 와 동일한 인과 구조: 예측 -> 다음 슬롯 재밍).
    %
    %   로그 필드는 TimeSlotR 과 동일:
    %     slot / observedChannel / jammingChannels / isAttackPhase
    %   -> final11 의 extractHitVectorGeneric(log, N, 'jammingChannels', 'observedChannel') 그대로 사용 가능
    % ================================================================

    properties
        ReconnaissanceDuration
        TopKJam = 2
        HistoryWindow = 50
        EnableJamming = true
        Verbose = false
    end

    properties (Access = private)
        % Target 채널 선택 이력 (관측 순서대로)
        History = []
    end

    methods

        function obj = TimeSlotP(reconnaissanceDuration, topKJam, historyWindow)
            if nargin < 1 || isempty(reconnaissanceDuration)
                error("TimeSlotP:MissingReconnaissanceDuration", ...
                    "reconnaissanceDuration 을 생성자에 전달해야 합니다.");
            end
            if nargin >= 2 && ~isempty(topKJam)
                obj.TopKJam = topKJam;
            end
            if nargin >= 3 && ~isempty(historyWindow)
                obj.HistoryWindow = historyWindow;
            end
            obj.ReconnaissanceDuration = reconnaissanceDuration;
        end

        %% ============================================================
        % Main Time-Slot Execution
        %   obj 는 value class 이므로 History 갱신을 위해 obj 를 반환한다.
        % =============================================================
        function [obj, pLog] = run(obj, slotIndex, UTs, Satellite, apj, ...
                ServiceChannels, ControlChannels, targetBeamIndex, pLog)

            %% 1. Channel 초기화
            obj.clearChannels(ServiceChannels, ControlChannels);

            %% 2. 재밍 채널 결정 (t-1 까지의 이력만 사용)
            isAttackPhase = slotIndex > obj.ReconnaissanceDuration;
            isJammingActive = isAttackPhase && obj.EnableJamming;

            jammingChannels = [];
            if isJammingActive
                jammingChannels = obj.predictChannels(numel(ServiceChannels));
            end

            if ~isempty(jammingChannels)
                apj.JammingChannel = jammingChannels(1);
            else
                apj.JammingChannel = [];
            end

            %% 3. Satellite Beam Action Selection (Target DQN 포함)
            currentSlotOccupancy = zeros(1, numel(ServiceChannels));
            targetAction = [];

            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);
                state = beam.StateManager.getState();
                beam.StateManager.setCurrentOccupancy(currentSlotOccupancy);
                occupancy = beam.StateManager.getCurrentOccupancy();

                beam.Agent.setCurrentState(state);
                beam.Agent.setCurrentOccupancy(occupancy);
                beam.Agent.completeTransition();
                beam.Agent.train();

                selectedChannel = beam.Agent.selectAction(state, occupancy);
                beam.SelectedChannel = selectedChannel;
                currentSlotOccupancy(selectedChannel) = currentSlotOccupancy(selectedChannel) + 1;

                if beamIndex == targetBeamIndex
                    targetAction = selectedChannel;
                end
            end

            if isempty(targetAction)
                error("TimeSlotP:TargetAgentNotFound", ...
                    "Target Beam %d 의 Agent 를 찾지 못했습니다.", targetBeamIndex);
            end

            %% 4. DATA 패킷 주입
            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);
                packet = Packet(PacketType.DATA, NodeType.Satellite, Satellite.Id, ...
                    NodeType.UT, beam.AssociatedUTId, beam.Id, ChannelType.Service, beam.SelectedChannel);
                ServiceChannels(packet.ChannelId).addPacket(packet);
            end

            %% 5. JAMMING 패킷 주입
            if isJammingActive && ~isempty(jammingChannels)
                targetBeamId = Satellite.Beams(targetBeamIndex).Id;
                for jammingChannel = jammingChannels
                    jamPacket = Packet(PacketType.JAMMING, NodeType.APJ, apj.Id, ...
                        NodeType.UT, apj.TargetUTId, targetBeamId, ChannelType.Service, jammingChannel);
                    ServiceChannels(jammingChannel).addPacket(jamPacket);
                end
            end

            %% 6. Target 행동 관측 -> 이력 갱신 (다음 슬롯 예측에 사용)
            apj.ObservedChannel = targetAction;
            obj.History(end + 1) = targetAction; %#ok<AGROW>
            if numel(obj.History) > obj.HistoryWindow
                obj.History = obj.History(end - obj.HistoryWindow + 1:end);
            end

            %% 7. 로그
            entry.slot = slotIndex;
            entry.observedChannel = targetAction;
            entry.jammingChannels = jammingChannels;
            entry.isAttackPhase = isAttackPhase;
            pLog(end + 1) = entry; %#ok<AGROW>

            if obj.Verbose
                fprintf("  [TimeSlotP] slot %d | target=%d | jam=%s | %s\n", ...
                    slotIndex, targetAction, mat2str(jammingChannels), ...
                    TimeSlotP.phaseToString(isAttackPhase));
            end

            %% 8. HARQ (각 UT 가 performHARQ 내부에서 observe() 수행)
            targetPacketType = [];
            targetSINR_dB = [];
            for utIndex = 1:numel(UTs)
                [packetType, SINR_dB] = UTs(utIndex).performHARQ(ServiceChannels, ControlChannels, Satellite, apj);
                if utIndex == apj.TargetUTId
                    targetPacketType = packetType;
                    targetSINR_dB = SINR_dB;
                end
            end

            %% 9. Feedback -> Target DQN reward
            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);
                ack = beam.receiveFeedback(ControlChannels, Satellite);
                beam.Agent.setReward(ack);
            end

            %% 10. Target UT 결과 기록 (computeAttackUTMetrics 에서 사용)
            DebugHelper.recordTargetUTOutcome(slotIndex, targetPacketType, targetSINR_dB, obj.ReconnaissanceDuration);
        end

        %% ============================================================
        % recency + frequency 예측
        % =============================================================
        function channels = predictChannels(obj, numChannels)
            channels = [];
            if isempty(obj.History)
                % 이력이 없으면 무작위 (정찰 >= 1 슬롯이면 발생하지 않음)
                perm = randperm(numChannels);
                channels = perm(1:min(obj.TopKJam, numChannels));
                return;
            end

            % 1) recency
            lastChannel = obj.History(end);
            channels = lastChannel;

            if obj.TopKJam < 2
                return;
            end

            % 2) frequency (동률이면 더 최근에 쓰인 채널 우선)
            counts = accumarray(obj.History(:), 1, [numChannels, 1])';
            lastUse = zeros(1, numChannels);
            for idx = 1:numel(obj.History)
                lastUse(obj.History(idx)) = idx;
            end
            counts(lastChannel) = -Inf;                     % 이미 선택된 채널 제외
            [~, order] = sortrows([-counts(:), -lastUse(:)]);
            for k = 1:numel(order)
                c = order(k);
                if c ~= lastChannel && counts(c) > 0
                    channels = [channels, c]; %#ok<AGROW>
                    break;
                end
            end

            % 최근 창에 채널이 하나뿐이면 나머지 무작위로 채움
            while numel(channels) < min(obj.TopKJam, numChannels)
                cand = setdiff(1:numChannels, channels);
                channels = [channels, cand(randi(numel(cand)))]; %#ok<AGROW>
            end
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
        function text = phaseToString(isAttackPhase)
            if isAttackPhase
                text = "ATTACK";
            else
                text = "RECONNAISSANCE";
            end
        end
    end
end