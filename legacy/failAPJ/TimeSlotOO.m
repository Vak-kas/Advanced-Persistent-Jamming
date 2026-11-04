classdef TimeSlotOO < handle

    properties
        ReconnaissanceDuration
    end


    methods

        %% ============================================================
        % Constructor
        %% ============================================================
        function obj = TimeSlotOO()

            env;

            obj.ReconnaissanceDuration = reconnaissanceDuration;

        end



        %% ============================================================
        % Time Slot
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
            % Transition Comparison용 임시 변수
            %% ========================================================

            beam1StateForCompare = [];
            beam1ActionForCompare = [];



            %% ========================================================
            % 2. Satellite Beam Channel Selection
            %% ========================================================

            currentSlotOccupancy = ...
                zeros(1, numel(ServiceChannels));


            for beamIndex = 1:numel(Satellite.Beams)

                beam = ...
                    Satellite.Beams(beamIndex);


                %% ----------------------------------------------------
                % 2.1 현재 State
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
                % ★ Beam1 S_t 저장
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
                % 2.4 DQN Training
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
                % 2.5 Action Selection
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
                % ★ Beam1 A_t 저장
                %% ----------------------------------------------------
                if beamIndex == 1

                    beam1ActionForCompare = ...
                        selectedChannel;

                end



                %% ----------------------------------------------------
                % Sequential Occupancy Update
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
            % Oracle Observation
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
            % Target UT 실제 HARQ
            %% --------------------------------------------------------
            actualTargetHARQ = ...
                harqResults{1};

            actualTargetACK = ...
                (actualTargetHARQ == PacketType.ACK);



            %% ========================================================
            % 6. Beam Feedback + Reward
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
            % ★ Beam1 R_t 저장
            %% --------------------------------------------------------
            beam1RewardForCompare = ...
                actualACK(1);



            %% --------------------------------------------------------
            % ★ Beam1 S_t+1 저장
            %% --------------------------------------------------------
            beam1NextStateForCompare = ...
                Satellite.Beams(1).StateManager.getState();



            %% ========================================================
            % 7. APJ - FULL ORACLE
            %% ========================================================

            %% --------------------------------------------------------
            % 7.1 APJ S_t
            %% --------------------------------------------------------
            apjState = ...
                APJ.StateManager.getState();


            predictionForCurrentSlot = ...
                APJ.PredictedChannel;


            apjOccupancy = ...
                zeros(1, numel(ServiceChannels));



            %% --------------------------------------------------------
            % 7.2 APJ 자체 RF sensing
            %
            % 학습에는 사용하지 않음.
            % pseudo SINR 평가용.
            %% --------------------------------------------------------
            APJ.ObservationManager.observe( ...
                ServiceChannels, ...
                Satellite ...
            );



            %% --------------------------------------------------------
            % 7.3 Target Beam Actual Action 관측
            %% --------------------------------------------------------
            observedChannel = ...
                APJ.findObservedChannel( ...
                    ServiceChannels ...
                );



            %% --------------------------------------------------------
            % 이전 Prediction 평가
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
            % 7.4 Pseudo SINR / HARQ
            %
            % OO 학습에는 사용하지 않고 평가용
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

            end



            %% ========================================================
            % 7.5 Full Oracle APJ Transition
            %% ========================================================

            if ~isempty(observedChannel)


                %% ----------------------------------------------------
                % APJ A_t
                %% ----------------------------------------------------
                APJ.Agent.observeAction( ...
                    apjState, ...
                    apjOccupancy, ...
                    observedChannel ...
                );



                %% ----------------------------------------------------
                % Oracle Reward
                %% ----------------------------------------------------
                APJ.Agent.setReward( ...
                    actualTargetACK ...
                );



                %% ----------------------------------------------------
                % Oracle State Update
                %
                % O = UT1 actual
                % A = Beam1 actual
                % H = UT1 actual
                %% ----------------------------------------------------
                APJ.StateManager.update( ...
                    oracleObservation, ...
                    observedChannel, ...
                    actualTargetHARQ ...
                );



                %% ----------------------------------------------------
                % APJ S_t+1
                %% ----------------------------------------------------
                apjNextState = ...
                    APJ.StateManager.getState();



                %% ====================================================
                % ★★★ Full Oracle Transition Equality Check ★★★
                %
                % Beam1:
                %   S_t
                %   A_t
                %   R_t
                %   S_t+1
                %
                % APJ:
                %   S_t
                %   A_t
                %   R_t
                %   S_t+1
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



                %% ----------------------------------------------------
                % Transition Complete
                %% ----------------------------------------------------
                APJ.Agent.setCurrentState( ...
                    apjNextState ...
                );

                APJ.Agent.setCurrentOccupancy( ...
                    zeros(1, numel(ServiceChannels)) ...
                );

                APJ.Agent.completeTransition();



                %% ----------------------------------------------------
                % APJ Training
                %% ----------------------------------------------------
                [apjLossValue, apjTrainingInfo] = ...
                    APJ.Agent.train();



                %% ----------------------------------------------------
                % Next Channel Prediction
                %% ----------------------------------------------------
                [predictedChannel, apjQValues] = ...
                    APJ.Agent.predictAction( ...
                        apjNextState, ...
                        zeros(1, numel(ServiceChannels)) ...
                    );


                APJ.PredictedChannel = ...
                    predictedChannel;



                %% ----------------------------------------------------
                % Debug
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
            % 7.6 APJ Jamming
            %
            % Oracle 검증 중 실제 packet 삽입 X
            %% ========================================================

            if slotIndex > obj.ReconnaissanceDuration && ...
               ~isempty(predictionForCurrentSlot)

                APJ.JammingChannel = ...
                    predictionForCurrentSlot;

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