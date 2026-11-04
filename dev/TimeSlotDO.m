classdef TimeSlotD
    % TimeSlotD
    %
    % ================================================================
    % Full-Oracle Independent Shadow DQN
    % ================================================================
    %
    % Target Beam:
    %   - 실제 BeamAgent
    %   - epsilon-greedy로 실제 환경 action 선택
    %   - 실제 reward로 DQN 학습
    %
    % APJ:
    %   - APJAgent
    %   - 자기 action으로 환경에 개입하지 않음
    %   - Target의 실제 transition을 Full Oracle로 전달받음
    %
    % Full Oracle transition:
    %
    %   (S_t, C_t, A_t, R_t, S_{t+1}, C_{t+1})
    %
    % Target / Shadow는 동일 transition을 받지만:
    %
    %   - Network initialization은 독립
    %   - ReplayBuffer.sample()도 독립
    %   - Adam optimizer state도 독립
    %
    % 매 슬롯:
    %   - Target training 상태
    %   - Shadow training 상태
    %   - Q-values
    %   - Full Oracle transition equality
    %   - Target/Shadow divergence
    %
    % 를 모두 출력한다.


    methods

        %% ============================================================
        % Constructor
        % ============================================================
        function obj = TimeSlotD()
        end


        %% ============================================================
        % Run One Time Slot
        % ============================================================
        function [divergenceLog, channelLog] = run( ...
                obj, ...
                slotIndex, ...
                UTs, ...
                Satellite, ...
                apjd, ...
                ServiceChannels, ...
                ControlChannels, ...
                targetBeamIndex, ...
                divergenceLog, ...
                channelLog)

            %% ========================================================
            % Time Slot Header
            % =========================================================
            DebugHelper.printTimeSlot(slotIndex);


            %% ========================================================
            % 1. Channel 초기화
            % =========================================================
            obj.clearChannels( ...
                ServiceChannels, ...
                ControlChannels);


            %% ========================================================
            % 2. Satellite Beam Action Selection
            % =========================================================
            currentSlotOccupancy = ...
                zeros(1, numel(ServiceChannels));


            % =========================================================
            % Target 관련 임시 변수
            % =========================================================
            targetBeam = [];
            targetAgent = [];

            targetState = [];
            targetOccupancy = [];
            targetAction = [];

            % 직전 슬롯 transition 비교용
            targetPrevState = [];
            targetPrevOccupancy = [];
            targetPrevAction = [];
            targetPrevReward = [];

            targetNextState = [];
            targetNextOccupancy = [];

            % Target training 결과
            lossTarget = [];
            trainingInfoTarget = struct( ...
                "MeanQValue", [], ...
                "MaxQValue", [], ...
                "MeanTargetQValue", []);


            %% ========================================================
            % Beam Loop
            % =========================================================
            for beamIndex = 1:numel(Satellite.Beams)

                beam = ...
                    Satellite.Beams(beamIndex);


                %% ----------------------------------------------------
                % 2-1. 현재 State S_t
                % -----------------------------------------------------
                state = ...
                    beam.StateManager.getState();


                %% ----------------------------------------------------
                % 2-2. 현재 Occupancy C_t
                % -----------------------------------------------------
                beam.StateManager.setCurrentOccupancy( ...
                    currentSlotOccupancy);

                occupancy = ...
                    beam.StateManager.getCurrentOccupancy();


                %% ----------------------------------------------------
                % 2-3. Target의 이전 transition 값 보존
                %
                % completeTransition() 후 Pending 값이 삭제되므로
                % 먼저 복사한다.
                % -----------------------------------------------------
                if beamIndex == targetBeamIndex

                    targetBeam = ...
                        beam;

                    targetAgent = ...
                        beam.Agent;

                    targetPrevState = ...
                        beam.Agent.PendingState;

                    targetPrevOccupancy = ...
                        beam.Agent.PendingOccupancy;

                    targetPrevAction = ...
                        beam.Agent.PendingAction;

                    targetPrevReward = ...
                        beam.Agent.PendingReward;

                    % 이번 슬롯은 이전 transition의 next state
                    targetNextState = ...
                        state;

                    targetNextOccupancy = ...
                        occupancy;
                end


                %% ----------------------------------------------------
                % 2-4. Current State 등록
                % -----------------------------------------------------
                beam.Agent.setCurrentState( ...
                    state);

                beam.Agent.setCurrentOccupancy( ...
                    occupancy);


                %% ----------------------------------------------------
                % 2-5. 이전 Transition 완성
                %
                % (S_{t-1}, C_{t-1}, A_{t-1}, R_{t-1},
                %  S_t, C_t)
                % -----------------------------------------------------
                beam.Agent.completeTransition();


                %% ----------------------------------------------------
                % 2-6. DQN 학습
                % -----------------------------------------------------
                [lossValue, trainingInfo] = ...
                    beam.Agent.train();


                %% ----------------------------------------------------
                % Target Training 결과 저장 + 매 슬롯 출력
                % -----------------------------------------------------
                if beamIndex == targetBeamIndex

                    lossTarget = ...
                        lossValue;

                    trainingInfoTarget = ...
                        trainingInfo;


                    % 기존 DebugHelper 이용
                    DebugHelper.printAgentTraining( ...
                        beam, ...
                        lossValue, ...
                        trainingInfo);

                end


                %% ----------------------------------------------------
                % 2-7. 이번 슬롯 Action A_t 선택
                % -----------------------------------------------------
                [selectedChannel, ...
                    selectionMethod, ...
                    randomValue, ...
                    qValues] = ...
                    beam.Agent.selectAction( ...
                        state, ...
                        occupancy);


                beam.SelectedChannel = ...
                    selectedChannel;


                %% ----------------------------------------------------
                % 2-8. 현재 Slot Occupancy 갱신
                % -----------------------------------------------------
                currentSlotOccupancy(selectedChannel) = ...
                    currentSlotOccupancy(selectedChannel) + 1;


                %% ----------------------------------------------------
                % 2-9. Target action / state 저장
                % -----------------------------------------------------
                if beamIndex == targetBeamIndex

                    targetState = ...
                        state;

                    targetOccupancy = ...
                        occupancy;

                    targetAction = ...
                        selectedChannel;


                    %% ================================================
                    % Target Action Selection Debug
                    % ================================================
                    fprintf("\n");
                    fprintf("============================================================\n");
                    fprintf("TARGET ACTION SELECTION - SLOT %d\n", slotIndex);
                    fprintf("============================================================\n");

                    fprintf("  Selection Method         : %s\n", ...
                        string(selectionMethod));

                    fprintf("  Random Value             : %.8f\n", ...
                        randomValue);

                    fprintf("  Selected Channel         : %d\n", ...
                        selectedChannel);

                    fprintf("  Epsilon After Selection  : %.8f\n", ...
                        beam.Agent.Epsilon);

                    if isempty(qValues)

                        fprintf("  Selection Q-values       : N/A (Random Action)\n");

                    else

                        qValuesDebug = ...
                            double(qValues(:));

                        [~, greedyChannel] = ...
                            max(qValuesDebug);

                        fprintf("\n");
                        fprintf("  [Q-values used for Action Selection]\n");

                        for channelIndex = 1:numel(qValuesDebug)

                            fprintf( ...
                                "    CH %2d : %+12.8f", ...
                                channelIndex, ...
                                qValuesDebug(channelIndex));

                            if channelIndex == greedyChannel
                                fprintf("  <-- Greedy");
                            end

                            if channelIndex == selectedChannel
                                fprintf("  <-- Selected");
                            end

                            fprintf("\n");

                        end

                    end

                    fprintf("============================================================\n");


                    %% ================================================
                    % Channel Log
                    % ================================================
                    channelEntry.slot = ...
                        slotIndex;

                    channelEntry.channel = ...
                        selectedChannel;

                    channelEntry.epsilon = ...
                        beam.Agent.Epsilon;

                    channelEntry.method = ...
                        selectionMethod;


                    if isempty(qValues)

                        channelEntry.qValues = ...
                            NaN(1, beam.Agent.NumActions);

                    else

                        channelEntry.qValues = ...
                            qValues(:)';

                    end


                    channelLog(end + 1) = ...
                        channelEntry; %#ok<AGROW>

                end

            end


            %% ========================================================
            % Target Beam 확인
            % =========================================================
            if isempty(targetAgent)

                error( ...
                    "TimeSlotD:TargetAgentNotFound", ...
                    "Target Beam %d의 Agent를 찾지 못했습니다.", ...
                    targetBeamIndex);

            end


            %% ========================================================
            % 3. Satellite → UT Downlink DATA 전송
            % =========================================================
            dataPackets = ...
                cell(1, numel(Satellite.Beams));


            for beamIndex = 1:numel(Satellite.Beams)

                beam = ...
                    Satellite.Beams(beamIndex);


                dataPackets{beamIndex} = ...
                    Packet( ...
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

                packet = ...
                    dataPackets{beamIndex};

                ServiceChannels( ...
                    packet.ChannelId).addPacket( ...
                        packet);

            end


            %% ========================================================
            % 4. APJ Full-Oracle Shadow DQN
            % =========================================================
            shadowAgent = ...
                apjd.Agent;


            %% --------------------------------------------------------
            % 4-1. Shadow에 Target의 현재 State / Occupancy Oracle 제공
            % ---------------------------------------------------------
            shadowState = ...
                targetState;

            shadowOccupancy = ...
                targetOccupancy;


            shadowAgent.setCurrentState( ...
                shadowState);

            shadowAgent.setCurrentOccupancy( ...
                shadowOccupancy);


            %% ========================================================
            % 4-2. Full Oracle Transition Equality Check
            %
            % 직전 슬롯 transition:
            %
            % Target:
            %   targetPrevState
            %   targetPrevOccupancy
            %   targetPrevAction
            %   targetPrevReward
            %
            % Shadow:
            %   PendingState
            %   PendingOccupancy
            %   PendingAction
            %   PendingReward
            %
            % =========================================================
            if ~isempty(targetPrevState) && ...
               ~isempty(shadowAgent.PendingState)

                fprintf("\n");
                fprintf("============================================================\n");
                fprintf("FULL ORACLE TRANSITION CHECK - SLOT %d\n", slotIndex);
                fprintf("============================================================\n");


                %% Previous State
                previousStateDiff = ...
                    norm( ...
                        double(targetPrevState(:)) - ...
                        double(shadowAgent.PendingState(:)));


                %% Previous Occupancy
                previousOccupancyDiff = ...
                    norm( ...
                        double(targetPrevOccupancy(:)) - ...
                        double(shadowAgent.PendingOccupancy(:)));


                %% Action Match
                actionMatch = ...
                    targetPrevAction == ...
                    shadowAgent.PendingAction;


                %% Reward Match
                rewardMatch = ...
                    targetPrevReward == ...
                    shadowAgent.PendingReward;


                %% Next State
                nextStateDiff = ...
                    norm( ...
                        double(targetNextState(:)) - ...
                        double(shadowState(:)));


                %% Next Occupancy
                nextOccupancyDiff = ...
                    norm( ...
                        double(targetNextOccupancy(:)) - ...
                        double(shadowOccupancy(:)));


                %% Print
                fprintf( ...
                    "  Previous State L2 Diff      : %.12f\n", ...
                    previousStateDiff);

                fprintf( ...
                    "  Previous Occupancy Diff     : %.12f\n", ...
                    previousOccupancyDiff);

                fprintf( ...
                    "  Previous Action Target      : %d\n", ...
                    targetPrevAction);

                fprintf( ...
                    "  Previous Action Shadow      : %d\n", ...
                    shadowAgent.PendingAction);

                fprintf( ...
                    "  Previous Reward Target      : %.8f\n", ...
                    targetPrevReward);

                fprintf( ...
                    "  Previous Reward Shadow      : %.8f\n", ...
                    shadowAgent.PendingReward);

                fprintf( ...
                    "  Next State L2 Diff          : %.12f\n", ...
                    nextStateDiff);

                fprintf( ...
                    "  Next Occupancy Diff         : %.12f\n", ...
                    nextOccupancyDiff);


                transitionExactMatch = ...
                    previousStateDiff == 0 && ...
                    previousOccupancyDiff == 0 && ...
                    actionMatch && ...
                    rewardMatch && ...
                    nextStateDiff == 0 && ...
                    nextOccupancyDiff == 0;


                if transitionExactMatch

                    fprintf( ...
                        "  Transition Exact Match      : YES\n");

                else

                    fprintf( ...
                        "  Transition Exact Match      : NO\n");

                end


                fprintf("============================================================\n");

            end


            %% --------------------------------------------------------
            % 4-3. Shadow 이전 Transition 완성
            % ---------------------------------------------------------
            shadowAgent.completeTransition();


            %% --------------------------------------------------------
            % 4-4. Shadow DQN 학습
            % ---------------------------------------------------------
            [lossShadow, trainingInfoShadow] = ...
                shadowAgent.train();


            %% ========================================================
            % 4-5. Shadow Agent Training 매 슬롯 출력
            % =========================================================
            TimeSlotD.printShadowTraining( ...
                slotIndex, ...
                shadowAgent, ...
                shadowState, ...
                shadowOccupancy, ...
                lossShadow, ...
                trainingInfoShadow);


            %% --------------------------------------------------------
            % 4-6. Target의 실제 Action을 Shadow의 transition으로 등록
            % ---------------------------------------------------------
            shadowAgent.observeAction( ...
                shadowState, ...
                shadowOccupancy, ...
                targetAction);


            apjd.ObservedChannel = ...
                targetAction;


            %% ========================================================
            % 4-7. Target / Shadow Q-vector 비교
            % =========================================================

            %% Target Q
            dlTargetState = ...
                targetAgent.convertStateToDLArray( ...
                    targetState);

            dlTargetOccupancy = ...
                targetAgent.convertOccupancyToDLArray( ...
                    targetOccupancy);


            qTarget = ...
                extractdata( ...
                    predict( ...
                        targetAgent.QNetwork, ...
                        dlTargetState, ...
                        dlTargetOccupancy));

            qTarget = ...
                double(qTarget(:));


            %% Shadow Q
            dlShadowState = ...
                shadowAgent.convertStateToDLArray( ...
                    shadowState);

            dlShadowOccupancy = ...
                shadowAgent.convertOccupancyToDLArray( ...
                    shadowOccupancy);


            qShadow = ...
                extractdata( ...
                    predict( ...
                        shadowAgent.QNetwork, ...
                        dlShadowState, ...
                        dlShadowOccupancy));

            qShadow = ...
                double(qShadow(:));


            %% Greedy
            [~, greedyTarget] = ...
                max(qTarget);

            [~, greedyShadow] = ...
                max(qShadow);


            %% Metrics
            qCosSim = ...
                dot(qTarget, qShadow) / ...
                ( ...
                    norm(qTarget) * ...
                    norm(qShadow) + eps ...
                );


            argmaxMatch = ...
                double( ...
                    greedyTarget == ...
                    greedyShadow);


            qL2Dist = ...
                norm( ...
                    qTarget - ...
                    qShadow);


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


            %% ========================================================
            % 4-8. Target vs Shadow 비교 출력
            % =========================================================
            fprintf("\n");
            fprintf("============================================================\n");
            fprintf("TARGET vs SHADOW DQN - SLOT %d\n", slotIndex);
            fprintf("============================================================\n");

            fprintf("  Target Actual Action     : CH%d\n", ...
                targetAction);

            fprintf("  Target Greedy Action     : CH%d\n", ...
                greedyTarget);

            fprintf("  Shadow Greedy Prediction : CH%d\n", ...
                greedyShadow);

            fprintf("\n");

            fprintf("  [Q-value Comparison]\n");

            for channelIndex = 1:numel(qTarget)

                fprintf( ...
                    "    CH %2d | Target=%+11.7f | Shadow=%+11.7f | Diff=%10.7f", ...
                    channelIndex, ...
                    qTarget(channelIndex), ...
                    qShadow(channelIndex), ...
                    abs(qTarget(channelIndex) - qShadow(channelIndex)));

                if channelIndex == greedyTarget
                    fprintf("  <- TargetGreedy");
                end

                if channelIndex == greedyShadow
                    fprintf("  <- ShadowGreedy");
                end

                fprintf("\n");

            end


            fprintf("\n");

            fprintf("  Q Cosine Similarity      : %.8f\n", ...
                qCosSim);

            fprintf("  Q L2 Distance            : %.8f\n", ...
                qL2Dist);

            fprintf("  Argmax Match             : %d\n", ...
                argmaxMatch);

            fprintf("  Weight Diff L2 Norm      : %.8f\n", ...
                weightDiffNorm);

            fprintf("  Target Weight Norm       : %.8f\n", ...
                weightNormTarget);

            fprintf("  Shadow Weight Norm       : %.8f\n", ...
                weightNormShadow);

            fprintf("============================================================\n");


            %% --------------------------------------------------------
            % Empty Loss -> NaN
            % ---------------------------------------------------------
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


            %% ========================================================
            % 4-9. Divergence Log
            % =========================================================
            entry.slot = ...
                slotIndex;

            entry.lossA = ...
                lossTargetLog;

            entry.lossB = ...
                lossShadowLog;

            entry.qCosSim = ...
                qCosSim;

            entry.argmaxMatch = ...
                argmaxMatch;

            entry.weightDiffNorm = ...
                weightDiffNorm;

            entry.weightNormA = ...
                weightNormTarget;

            entry.weightNormB = ...
                weightNormShadow;

            entry.qA = ...
                qTarget(:)';

            entry.qB = ...
                qShadow(:)';

            entry.qL2Dist = ...
                qL2Dist;

            entry.observedChannel = ...
                targetAction;

            entry.actualACK = ...
                NaN;


            divergenceLog(end + 1) = ...
                entry; %#ok<AGROW>


            %% ========================================================
            % 5. UT HARQ 수행
            % =========================================================
            harqResults = ...
                cell(1, numel(UTs));

            sinrResults_dB = ...
                zeros(1, numel(UTs));

            targetPacketType = [];


            for utIndex = 1:numel(UTs)

                [packetType, SINR_dB] = ...
                    UTs(utIndex).performHARQ( ...
                        ServiceChannels, ...
                        ControlChannels, ...
                        Satellite, ...
                        apjd);


                harqResults{utIndex} = ...
                    packetType;

                sinrResults_dB(utIndex) = ...
                    SINR_dB;


                if utIndex == apjd.TargetUTId

                    targetPacketType = ...
                        packetType;

                end

            end


            %% ========================================================
            % 6. Beam이 Feedback 수신 / Reward 저장
            % =========================================================
            actualACK = ...
                false(1, numel(Satellite.Beams));


            for beamIndex = 1:numel(Satellite.Beams)

                beam = ...
                    Satellite.Beams(beamIndex);


                actualACK(beamIndex) = ...
                    beam.receiveFeedback( ...
                        ControlChannels, ...
                        Satellite);


                beam.Agent.setReward( ...
                    actualACK(beamIndex));

            end


            %% ========================================================
            % 7. Shadow Full-Oracle Reward
            % =========================================================
            targetOutcome = ...
                actualACK(targetBeamIndex);


            shadowAgent.setReward( ...
                targetOutcome);


            %% ========================================================
            % Reward 등록 확인
            % =========================================================
            fprintf("\n");
            fprintf("============================================================\n");
            fprintf("REWARD RESULT - SLOT %d\n", slotIndex);
            fprintf("============================================================\n");

            fprintf("  Target Channel           : CH%d\n", ...
                targetAction);

            fprintf("  HARQ                     : %s\n", ...
                TimeSlotD.packetTypeToString(targetPacketType));

            fprintf("  Target Outcome           : %d\n", ...
                targetOutcome);

            fprintf("  Target Pending Reward    : %.8f\n", ...
                targetAgent.PendingReward);

            fprintf("  Shadow Pending Reward    : %.8f\n", ...
                shadowAgent.PendingReward);

            fprintf("============================================================\n");


            %% ========================================================
            % 8. APJ StateManager Update
            % =========================================================
            targetUTFeedbackObservation = [];


            controlPackets = ...
                ControlChannels( ...
                    targetAction).getPackets();


            for packetIndex = 1:numel(controlPackets)

                packet = ...
                    controlPackets(packetIndex);


                if packet.SourceType == NodeType.UT && ...
                   packet.SourceId == apjd.TargetUTId

                    targetUTFeedbackObservation = ...
                        packet.Payload;

                    break;

                end

            end


            if ~isempty(targetUTFeedbackObservation)

                apjd.StateManager.update( ...
                    targetUTFeedbackObservation, ...
                    targetAction, ...
                    targetPacketType);

            end


            %% ========================================================
            % 9. ACK Log
            % =========================================================
            if ~isempty(divergenceLog) && ...
               divergenceLog(end).slot == slotIndex

                divergenceLog(end).actualACK = ...
                    double(targetOutcome);

            end


            %% ========================================================
            % 10. Shadow Prediction 저장
            % =========================================================
            [predictedAction, predictedQValues] = ...
                shadowAgent.predictAction( ...
                    shadowState, ...
                    shadowOccupancy);


            apjd.PredictedChannel = ...
                predictedAction;

            apjd.PredictedQValues = ...
                predictedQValues;

        end


        %% ============================================================
        % Channel Clear
        % ============================================================
        function clearChannels( ...
                ~, ...
                ServiceChannels, ...
                ControlChannels)

            for channelIndex = 1:numel(ServiceChannels)

                ServiceChannels( ...
                    channelIndex).clearPacket();

            end


            for channelIndex = 1:numel(ControlChannels)

                ControlChannels( ...
                    channelIndex).clearPacket();

            end

        end

    end


    methods (Static)

        %% ============================================================
        % Shadow Training 출력
        % ============================================================
        function printShadowTraining( ...
                slotIndex, ...
                shadowAgent, ...
                state, ...
                occupancy, ...
                lossValue, ...
                trainingInfo)

            fprintf("\n");
            fprintf("============================================================\n");
            fprintf("APJ SHADOW AGENT TRAINING - SLOT %d\n", slotIndex);
            fprintf("============================================================\n");


            fprintf("  Replay Buffer Count      : %d / %d\n", ...
                shadowAgent.ReplayBuffer.Count, ...
                shadowAgent.ReplayBuffer.Capacity);

            fprintf("  Batch Size               : %d\n", ...
                shadowAgent.BatchSize);

            fprintf("  Training Step            : %d\n", ...
                shadowAgent.TrainingStep);


            fprintf("\n");
            fprintf("  [Training]\n");


            if isempty(lossValue)

                fprintf("    Status                 : SKIPPED\n");
                fprintf("    Reason                 : Replay Buffer not ready\n");

            else

                fprintf("    Status                 : EXECUTED\n");

                fprintf("    Loss                   : %.8f\n", ...
                    lossValue);

                fprintf("    Mean Q-Value           : %.8f\n", ...
                    trainingInfo.MeanQValue);

                fprintf("    Max Q-Value            : %.8f\n", ...
                    trainingInfo.MaxQValue);

                fprintf("    Mean Target Q-Value    : %.8f\n", ...
                    trainingInfo.MeanTargetQValue);

            end


            %% --------------------------------------------------------
            % 현재 Shadow Q-values
            % ---------------------------------------------------------
            dlState = ...
                shadowAgent.convertStateToDLArray( ...
                    state);

            dlOccupancy = ...
                shadowAgent.convertOccupancyToDLArray( ...
                    occupancy);


            dlQValues = ...
                predict( ...
                    shadowAgent.QNetwork, ...
                    dlState, ...
                    dlOccupancy);


            qValues = ...
                double( ...
                    extractdata(dlQValues));

            qValues = ...
                qValues(:);


            [maxQValue, greedyAction] = ...
                max(qValues);


            fprintf("\n");
            fprintf("  [Current Shadow Q-Values]\n");


            for channelIndex = 1:numel(qValues)

                fprintf( ...
                    "    CH %2d : %+12.8f", ...
                    channelIndex, ...
                    qValues(channelIndex));

                if channelIndex == greedyAction

                    fprintf("  <-- Greedy");

                end

                fprintf("\n");

            end


            fprintf("\n");

            fprintf("  Greedy Action            : CH%d\n", ...
                greedyAction);

            fprintf("  Max Q                    : %.8f\n", ...
                maxQValue);

            fprintf("  Q Range                  : %.8f\n", ...
                max(qValues) - min(qValues));

            fprintf("  Q Std                    : %.8f\n", ...
                std(qValues));

            fprintf("============================================================\n");

        end


        %% ============================================================
        % Weight Difference L2 Norm
        % ============================================================
        function normDiff = ...
                computeWeightDiffNorm( ...
                    networkA, ...
                    networkB)

            learnA = ...
                networkA.Learnables;

            learnB = ...
                networkB.Learnables;


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


                if ~isequal( ...
                        size(valueA), ...
                        size(valueB))

                    error( ...
                        "TimeSlotD:NetworkParameterSizeMismatch", ...
                        "Target/Shadow parameter size가 다릅니다.");

                end


                difference = ...
                    valueA(:) - ...
                    valueB(:);


                sumSquares = ...
                    sumSquares + ...
                    sum(difference .^ 2);

            end


            normDiff = ...
                sqrt(sumSquares);

        end


        %% ============================================================
        % Network Weight L2 Norm
        % ============================================================
        function normValue = ...
                computeNetworkNorm(network)

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


        %% ============================================================
        % PacketType -> String
        % ============================================================
        function text = packetTypeToString(packetType)

            if isempty(packetType)

                text = "NONE";

            elseif packetType == PacketType.ACK

                text = "ACK";

            elseif packetType == PacketType.NACK

                text = "NACK";

            else

                text = "UNKNOWN";

            end

        end

    end

end