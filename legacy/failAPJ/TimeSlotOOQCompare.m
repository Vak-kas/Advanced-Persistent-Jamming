classdef TimeSlotOOQCompare < handle

    properties
        ReconnaissanceDuration

        % Q-policy 비교/누적 평가기
        QPolicyEvaluator
    end


    methods

        %% ============================================================
        % Constructor
        %% ============================================================
        function obj = TimeSlotOOQCompare(qPolicyEvaluator)

            env;

            obj.ReconnaissanceDuration = ...
                reconnaissanceDuration;

            obj.QPolicyEvaluator = ...
                qPolicyEvaluator;

        end



        %% ============================================================
        % Time Slot Run
        %% ============================================================
        function [harqResults, ...
                  sinrResults_dB, ...
                  actualTargetACK, ...
                  successRatio, ...
                  pseudoTargetACK, ...
                  estimatedTargetSINR_dB] = ...
                  run(obj, ...
                      slotIndex, ...
                      UTs, ...
                      Satellite, ...
                      APJ, ...
                      ServiceChannels, ...
                      ControlChannels)


            DebugHelper.printTimeSlot(slotIndex);


            %% ========================================================
            % 1. 채널 초기화
            %% ========================================================

            obj.clearChannels( ...
                ServiceChannels, ...
                ControlChannels ...
            );


            %% ========================================================
            % Transition 비교용 변수
            %% ========================================================

            beam1StateForCompare = [];
            beam1ActionForCompare = [];
            beam1RewardForCompare = [];
            beam1NextStateForCompare = [];


            %% ========================================================
            % 2. Satellite Beam Channel Selection
            %% ========================================================

            currentSlotOccupancy = ...
                zeros(1, numel(ServiceChannels));


            for beamIndex = 1:numel(Satellite.Beams)

                beam = ...
                    Satellite.Beams(beamIndex);


                %% ----------------------------------------------------
                % 2.1 현재 State S_t
                %% ----------------------------------------------------

                state = ...
                    beam.StateManager.getState();


                %% ----------------------------------------------------
                % 2.2 Sequential Occupancy
                %% ----------------------------------------------------

                beam.StateManager.setCurrentOccupancy( ...
                    currentSlotOccupancy ...
                );

                occupancy = ...
                    beam.StateManager.getCurrentOccupancy();


                %% ----------------------------------------------------
                % Beam1 S_t 저장
                %% ----------------------------------------------------

                if beamIndex == 1

                    beam1StateForCompare = ...
                        state;

                end


                %% ----------------------------------------------------
                % 2.3 이전 Transition 완성
                %% ----------------------------------------------------

                beam.Agent.setCurrentState( ...
                    state ...
                );

                beam.Agent.setCurrentOccupancy( ...
                    occupancy ...
                );

                beam.Agent.completeTransition();


                %% ----------------------------------------------------
                % 2.4 Beam DQN Training
                %% ----------------------------------------------------

                [lossValue, trainingInfo] = ...
                    beam.Agent.train();


                if beamIndex == 1

                    DebugHelper.printAgentTraining( ...
                        beam, ...
                        lossValue, ...
                        trainingInfo ...
                    );

                end


                %% ----------------------------------------------------
                % 2.5 현재 Slot Action 선택
                %% ----------------------------------------------------

                [selectedChannel, ...
                 selectionMethod, ...
                 randomValue, ...
                 qValues] = ...
                    beam.Agent.selectAction( ...
                        state, ...
                        occupancy ...
                    );


                beam.SelectedChannel = ...
                    selectedChannel;


                %% ----------------------------------------------------
                % Beam1 A_t 저장
                %% ----------------------------------------------------

                if beamIndex == 1

                    beam1ActionForCompare = ...
                        selectedChannel;

                end


                %% ----------------------------------------------------
                % Occupancy Update
                %% ----------------------------------------------------

                currentSlotOccupancy(selectedChannel) = ...
                    currentSlotOccupancy(selectedChannel) + 1;

            end



            %% ========================================================
            % 3. Satellite Downlink Transmission
            %% ========================================================

            dataPackets = ...
                cell(1, numel(Satellite.Beams));


            for beamIndex = 1:numel(Satellite.Beams)

                beam = ...
                    Satellite.Beams(beamIndex);


                selectedChannel = ...
                    beam.SelectedChannel;


                destinationUTId = ...
                    beam.AssociatedUTId;


                dataPackets{beamIndex} = ...
                    Packet( ...
                        PacketType.DATA, ...
                        NodeType.Satellite, ...
                        Satellite.Id, ...
                        NodeType.UT, ...
                        destinationUTId, ...
                        beam.Id, ...
                        ChannelType.Service, ...
                        selectedChannel ...
                    );

            end


            %% --------------------------------------------------------
            % Service Channel에 Packet 삽입
            %% --------------------------------------------------------

            for beamIndex = 1:numel(dataPackets)

                packet = ...
                    dataPackets{beamIndex};


                selectedChannel = ...
                    packet.ChannelId;


                ServiceChannels(selectedChannel).addPacket( ...
                    packet ...
                );

            end



            %% ========================================================
            % 4. UT RF Sensing
            %% ========================================================

            for utIndex = 1:numel(UTs)

                UTs(utIndex).ObservationManager.observe( ...
                    ServiceChannels, ...
                    Satellite ...
                );

            end


            %% --------------------------------------------------------
            % Full Oracle Observation
            %
            % Target UT1의 실제 observation
            %% --------------------------------------------------------

            oracleObservation = ...
                UTs(1).ObservationManager.getCurrentObservation();



            %% ========================================================
            % 5. UT HARQ
            %% ========================================================

            harqResults = ...
                cell(1, numel(UTs));


            sinrResults_dB = ...
                zeros(1, numel(UTs));


            for utIndex = 1:numel(UTs)

                [packetType, SINR_dB] = ...
                    UTs(utIndex).performHARQ( ...
                        ServiceChannels, ...
                        ControlChannels, ...
                        Satellite ...
                    );


                harqResults{utIndex} = ...
                    packetType;


                sinrResults_dB(utIndex) = ...
                    SINR_dB;

            end


            %% --------------------------------------------------------
            % Target UT Actual HARQ
            %% --------------------------------------------------------

            actualTargetHARQ = ...
                harqResults{1};


            actualTargetACK = ...
                (actualTargetHARQ == PacketType.ACK);



            %% ========================================================
            % 6. Beam Feedback + Reward 저장
            %% ========================================================

            actualACK = ...
                false(1, numel(Satellite.Beams));


            for beamIndex = 1:numel(Satellite.Beams)

                beam = ...
                    Satellite.Beams(beamIndex);


                actualACK(beamIndex) = ...
                    beam.receiveFeedback( ...
                        ControlChannels, ...
                        Satellite ...
                    );


                beam.Agent.setReward( ...
                    actualACK(beamIndex) ...
                );

            end


            %% --------------------------------------------------------
            % Beam1 R_t 저장
            %% --------------------------------------------------------

            beam1RewardForCompare = ...
                actualACK(1);


            %% --------------------------------------------------------
            % Beam1 S_t+1
            %% --------------------------------------------------------

            beam1NextStateForCompare = ...
                Satellite.Beams(1).StateManager.getState();



            %% ========================================================
            % 7. APJ Full Oracle Shadow Learning
            %% ========================================================

            %% --------------------------------------------------------
            % 7.1 APJ 현재 State S_t
            %% --------------------------------------------------------

            apjState = ...
                APJ.StateManager.getState();


            predictionForCurrentSlot = ...
                APJ.PredictedChannel;


            %% --------------------------------------------------------
            % Target Beam1은 항상 첫 번째 선택자
            %% --------------------------------------------------------

            apjOccupancy = ...
                zeros(1, numel(ServiceChannels));


            %% --------------------------------------------------------
            % APJ 자체 RF sensing
            %
            % Full Oracle training에는 사용 X
            % pseudo SINR 평가용
            %% --------------------------------------------------------

            APJ.ObservationManager.observe( ...
                ServiceChannels, ...
                Satellite ...
            );


            %% --------------------------------------------------------
            % Target Beam 실제 사용 채널
            %% --------------------------------------------------------

            observedChannel = ...
                APJ.findObservedChannel( ...
                    ServiceChannels ...
                );


            %% --------------------------------------------------------
            % 이전 Slot에서 예측했던 채널 평가
            %% --------------------------------------------------------

            if ~isempty(predictionForCurrentSlot) && ...
               ~isempty(observedChannel)

                DebugHelper.recordAPJPrediction( ...
                    slotIndex, ...
                    predictionForCurrentSlot, ...
                    observedChannel ...
                );

            end


            %% --------------------------------------------------------
            % APJ Estimated SINR
            %
            % Full Oracle 학습에는 사용하지 않음
            % pseudo HARQ 평가용
            %% --------------------------------------------------------

            estimatedTargetSINR_dB = ...
                APJ.estimateTargetSINR( ...
                    ServiceChannels, ...
                    Satellite ...
                );


            pseudoTargetACK = [];


            if ~isempty(estimatedTargetSINR_dB)

                pseudoHARQ = ...
                    APJ.generatePseudoHARQ( ...
                        estimatedTargetSINR_dB ...
                    );


                pseudoTargetACK = ...
                    (pseudoHARQ == PacketType.ACK);

            else

                pseudoHARQ = [];

            end



            %% ========================================================
            % 7.2 Full Oracle Transition
            %% ========================================================

            if ~isempty(observedChannel)


                %% ----------------------------------------------------
                % A_t = Beam1 Actual Action
                %% ----------------------------------------------------

                APJ.Agent.observeAction( ...
                    apjState, ...
                    apjOccupancy, ...
                    observedChannel ...
                );


                %% ----------------------------------------------------
                % R_t = Actual Target Reward
                %% ----------------------------------------------------

                APJ.Agent.setReward( ...
                    actualTargetACK ...
                );


                %% ----------------------------------------------------
                % S_t+1 구성
                %
                % O = Oracle UT1 Observation
                % A = Actual Beam1 Action
                % H = Actual UT1 HARQ
                %% ----------------------------------------------------

                APJ.StateManager.update( ...
                    oracleObservation, ...
                    observedChannel, ...
                    actualTargetHARQ ...
                );


                %% ----------------------------------------------------
                % APJ Next State
                %% ----------------------------------------------------

                apjNextState = ...
                    APJ.StateManager.getState();



                %% ====================================================
                % 7.3 Full Oracle Transition Equality Check
                %% ====================================================

                DebugHelper.compareOracleTransitions( ...
                    slotIndex, ...
                    beam1StateForCompare, ...
                    beam1ActionForCompare, ...
                    beam1RewardForCompare, ...
                    beam1NextStateForCompare, ...
                    apjState, ...
                    observedChannel, ...
                    actualTargetACK, ...
                    apjNextState ...
                );



                %% ====================================================
                % 7.4 동일 S_t+1에서 PRE APJ TRAIN Q 비교
                %% ====================================================

                compareOccupancy = ...
                    zeros(1, numel(ServiceChannels));


                beamQBefore = ...
                    obj.evaluateQNetwork( ...
                        Satellite.Beams(1).Agent, ...
                        beam1NextStateForCompare, ...
                        compareOccupancy ...
                    );


                apjQBefore = ...
                    obj.evaluateQNetwork( ...
                        APJ.Agent, ...
                        beam1NextStateForCompare, ...
                        compareOccupancy ...
                    );


                DebugHelper.compareBeamAPJQValues( ...
                    slotIndex, ...
                    "PRE_APJ_TRAIN", ...
                    beamQBefore, ...
                    apjQBefore ...
                );



                %% ====================================================
                % 7.5 APJ Transition Complete
                %% ====================================================

                APJ.Agent.setCurrentState( ...
                    apjNextState ...
                );


                APJ.Agent.setCurrentOccupancy( ...
                    zeros(1, numel(ServiceChannels)) ...
                );


                APJ.Agent.completeTransition();



                %% ====================================================
                % 7.6 APJ Training
                %% ====================================================

                [apjLossValue, apjTrainingInfo] = ...
                    APJ.Agent.train();



                %% ====================================================
                % 7.7 동일 S_t+1에서 POST APJ TRAIN Q 비교
                %% ====================================================

                beamQAfter = ...
                    obj.evaluateQNetwork( ...
                        Satellite.Beams(1).Agent, ...
                        beam1NextStateForCompare, ...
                        compareOccupancy ...
                    );


                apjQAfter = ...
                    obj.evaluateQNetwork( ...
                        APJ.Agent, ...
                        beam1NextStateForCompare, ...
                        compareOccupancy ...
                    );


                %% ----------------------------------------------------
                % 상세 Q-vector Debug 출력
                %% ----------------------------------------------------

                DebugHelper.compareBeamAPJQValues( ...
                    slotIndex, ...
                    "POST_APJ_TRAIN", ...
                    beamQAfter, ...
                    apjQAfter ...
                );


                %% ====================================================
                % ★ 최종 Q-Policy Shadowing Evaluator 기록
                %
                % 실제 prediction에 쓰이는 POST-TRAIN 기준
                %% ====================================================

                if ~isempty(obj.QPolicyEvaluator)

                    obj.QPolicyEvaluator.record( ...
                        slotIndex, ...
                        beamQAfter, ...
                        apjQAfter ...
                    );


                    obj.QPolicyEvaluator.printCurrent();

                end



                %% ====================================================
                % 7.8 APJ Next Channel Prediction
                %% ====================================================

                [predictedChannel, apjQValues] = ...
                    APJ.Agent.predictAction( ...
                        apjNextState, ...
                        zeros(1, numel(ServiceChannels)) ...
                    );


                APJ.PredictedChannel = ...
                    predictedChannel;



                %% ----------------------------------------------------
                % APJ Training Debug
                %
                % Full Oracle이므로 실제 HARQ 전달
                %% ----------------------------------------------------

                DebugHelper.printAPJTraining( ...
                    APJ, ...
                    slotIndex, ...
                    observedChannel, ...
                    estimatedTargetSINR_dB, ...
                    actualTargetHARQ, ...
                    apjLossValue, ...
                    apjTrainingInfo, ...
                    apjQValues ...
                );

            end



            %% ========================================================
            % 7.9 APJ Jamming
            %
            % 현재 OO 분석에서는 실제 jamming packet 미삽입
            %% ========================================================

            if slotIndex > obj.ReconnaissanceDuration && ...
               ~isempty(predictionForCurrentSlot)

                APJ.JammingChannel = ...
                    predictionForCurrentSlot;


                % 실제 공격 구현 시:
                %
                % 1. Jamming Packet 생성
                % 2. ServiceChannels(APJ.JammingChannel)에 삽입
                %
                % 여기에서 처리

            end



            %% ========================================================
            % 8. 결과 반환
            %% ========================================================

            numACK = 0;


            for utIndex = 1:numel(UTs)

                if harqResults{utIndex} == PacketType.ACK

                    numACK = ...
                        numACK + 1;

                end

            end


            successRatio = ...
                numACK / numel(UTs);

        end



        %% ============================================================
        % 동일 State를 특정 Agent Q-Network에 입력
        %% ============================================================
        function qValues = evaluateQNetwork( ...
                obj, ...
                agent, ...
                state, ...
                occupancy)


            dlState = ...
                agent.convertStateToDLArray( ...
                    state ...
                );


            dlOccupancy = ...
                agent.convertOccupancyToDLArray( ...
                    occupancy ...
                );


            dlQValues = ...
                predict( ...
                    agent.QNetwork, ...
                    dlState, ...
                    dlOccupancy ...
                );


            qValues = ...
                extractdata(dlQValues);


            qValues = ...
                double(qValues(:));

        end



        %% ============================================================
        % Channel Clear
        %% ============================================================
        function clearChannels( ...
                obj, ...
                ServiceChannels, ...
                ControlChannels)


            for channelIndex = 1:numel(ServiceChannels)

                ServiceChannels(channelIndex).clearPacket();

            end


            for channelIndex = 1:numel(ControlChannels)

                ControlChannels(channelIndex).clearPacket();

            end

        end

    end
end