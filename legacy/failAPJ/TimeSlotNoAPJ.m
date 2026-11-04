classdef TimeSlotNoAPJ < handle

    properties
        ReconnaissanceDuration

        % ============================================================
        % Beam1 Self-Prediction
        % ============================================================
        %
        % Slot t 끝에서 Beam1 자신의 Q-network로
        % Slot t+1 행동을 예측해 저장
        %
        Beam1PredictedChannel
    end


    methods

        %% ============================================================
        % Constructor
        %% ============================================================
        function obj = TimeSlotNoAPJ()

            env;

            obj.ReconnaissanceDuration = ...
                reconnaissanceDuration;

            obj.Beam1PredictedChannel = [];

        end



        %% ============================================================
        % Time Slot Run
        %% ============================================================
        function [harqResults, ...
                  sinrResults_dB, ...
                  actualTargetACK, ...
                  successRatio] = ...
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
            % 2. Satellite Beam 채널 선택
            %
            %    1) 현재 S_t / Occupancy 확보
            %    2) 이전 Transition 완성
            %    3) DQN 학습
            %    4) 현재 Action a_t 선택
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
                % 2.3 이전 Slot Transition 완성
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


                %% ----------------------------------------------------
                % ★ Beam1 Self-Prediction 평가
                %
                % 이전 Slot 끝에서 예측해둔
                %
                %       â_t
                %
                % 와 현재 실제 선택
                %
                %       a_t
                %
                % 비교
                %% ----------------------------------------------------
                if beamIndex == 1 && ...
                   ~isempty(obj.Beam1PredictedChannel)

                    DebugHelper.recordBeamSelfPrediction( ...
                        slotIndex, ...
                        obj.Beam1PredictedChannel, ...
                        selectedChannel ...
                    );

                end


                %% ----------------------------------------------------
                % 실제 선택 Channel 저장
                %% ----------------------------------------------------
                beam.SelectedChannel = ...
                    selectedChannel;


                %% ----------------------------------------------------
                % Sequential Occupancy Update
                %% ----------------------------------------------------
                currentSlotOccupancy(selectedChannel) = ...
                    currentSlotOccupancy(selectedChannel) + 1;


                if beamIndex == 1

                    % 필요 시 선택 방식 확인
                    %
                    % DebugHelper.printBeamActionSelection( ...
                    %     beam, ...
                    %     selectionMethod, ...
                    %     randomValue, ...
                    %     qValues ...
                    % );

                end

            end



            %% ========================================================
            % 3. Satellite Downlink Transmission
            %% ========================================================

            dataPackets = ...
                cell(1, numel(Satellite.Beams));


            %% --------------------------------------------------------
            % DATA Packet 생성
            %% --------------------------------------------------------
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
            % Service Channel에 DATA Packet 삽입
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
            % 4. UT RF Environment Sensing
            %% ========================================================

            for utIndex = 1:numel(UTs)

                UTs(utIndex).ObservationManager.observe( ...
                    ServiceChannels, ...
                    Satellite ...
                );

            end


            % APJ는 이 실험에서 학습/예측하지 않음.
            % 기존 구조 유지가 필요하면 sensing만 수행.
            if ~isempty(APJ)

                APJ.ObservationManager.observe( ...
                    ServiceChannels, ...
                    Satellite ...
                );

            end



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



            %% ========================================================
            % 6. Beam이 UT Feedback 수신 + Reward 저장
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



            %% ========================================================
            % 7. ★ Beam1 Self Next-Channel Prediction
            %
            % 현재 Slot t의 Observation / Action / HARQ가
            % StateManager에 반영된 상태.
            %
            % 따라서 현재 State는 다음 Slot에서 사용하게 될
            % S_{t+1}에 해당.
            %
            % 현재 Beam1 Q-network를 이용해:
            %
            % â_{t+1} = argmax_a Q(S_{t+1}, a)
            %
            % 계산.
            %% ========================================================

            beam1 = ...
                Satellite.Beams(1);


            %% --------------------------------------------------------
            % 다음 Slot State
            %% --------------------------------------------------------
            nextState = ...
                beam1.StateManager.getState();


            %% --------------------------------------------------------
            % Beam1은 항상 첫 번째 순차 선택자이므로
            % 다음 Slot Occupancy는 zero vector
            %% --------------------------------------------------------
            nextOccupancy = ...
                zeros(1, numel(ServiceChannels));


            %% --------------------------------------------------------
            % Deep Learning Input 변환
            %% --------------------------------------------------------
            dlNextState = ...
                beam1.Agent.convertStateToDLArray( ...
                    nextState ...
                );

            dlNextOccupancy = ...
                beam1.Agent.convertOccupancyToDLArray( ...
                    nextOccupancy ...
                );


            %% --------------------------------------------------------
            % Beam1 자신의 Q-Network으로 Prediction
            %% --------------------------------------------------------
            dlSelfQValues = ...
                predict( ...
                    beam1.Agent.QNetwork, ...
                    dlNextState, ...
                    dlNextOccupancy ...
                );


            selfQValues = ...
                extractdata(dlSelfQValues);

            selfQValues = ...
                selfQValues(:);


            %% --------------------------------------------------------
            % Greedy Next Channel
            %% --------------------------------------------------------
            [~, selfPredictedChannel] = ...
                max(selfQValues);


            obj.Beam1PredictedChannel = ...
                double(selfPredictedChannel);


            %% --------------------------------------------------------
            % Debug: 다음 슬롯 Self Prediction Q-values
            %% --------------------------------------------------------
            DebugHelper.printBeamSelfPredictionQValues( ...
                slotIndex, ...
                obj.Beam1PredictedChannel, ...
                selfQValues ...
            );



            %% ========================================================
            % 8. 결과 반환
            %% ========================================================

            actualTargetACK = ...
                (harqResults{1} == PacketType.ACK);


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