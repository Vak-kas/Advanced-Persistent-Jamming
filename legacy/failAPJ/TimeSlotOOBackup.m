classdef TimeSlotOO
    properties
        ReconnaissanceDuration
        % BeamLearnRate
    end
    methods
        function obj = TimeSlotOO()
            env;
            obj.ReconnaissanceDuration = reconnaissanceDuration;
            % obj.BeamLearnRate = beamLearnRate;
        end

        function [harqResults, sinrResults_dB, actualTargetACK, successRatio, pseudoTargetACK, estimatedTargetSINR_dB] = run(obj, slotIndex, UTs, Satellite, APJ, ServiceChannels, ControlChannels)
            DebugHelper.printTimeSlot(slotIndex);

            %% 1. 채널 초기화
            obj.clearChannels(ServiceChannels, ControlChannels);

            %% 2. Satellite beam의 채널 선택 (Action a_t 선택) + Transition 완성 + 학습
            currentSlotOccupancy = zeros(1, numel(ServiceChannels));
            % mainLearnerIndex = mod(slotIndex-1, numel(Satellite.Beams)) + 1;   % Multi-Timescale: 라운드로빈 순번

            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);
                state = beam.StateManager.getState();
                beam.StateManager.setCurrentOccupancy(currentSlotOccupancy);
                occupancy = beam.StateManager.getCurrentOccupancy();

                % occupancy가 확정되는 유일한 순간 — 이전 슬롯 transition을 완성
                beam.Agent.setCurrentState(state);
                beam.Agent.setCurrentOccupancy(occupancy);
                beam.Agent.completeTransition();

                % 방금 완성된 transition으로 즉시 학습 (다음 행동 선택 전에 최신 가중치 반영)
                [lossValue, trainingInfo] = beam.Agent.train();
                if beamIndex == 1
                    DebugHelper.printAgentTraining(beam, lossValue, trainingInfo);
                end

                % 이번 슬롯 행동 선택 (a_t)
                [selectedChannel, selectionMethod, randomValue, qValues] = beam.Agent.selectAction(state, occupancy);
                % selectedChannel = randi(numel(ServiceChannels));

                beam.SelectedChannel = selectedChannel;
                currentSlotOccupancy(selectedChannel) = currentSlotOccupancy(selectedChannel) + 1;

                if beamIndex == 1
                    % DebugHelper.recordBeamPolicy(slotIndex, qValues);
                end
            end

            %% 3. Satellite가 해당 채널로 DL 전송
            dataPackets = cell(1, numel(Satellite.Beams));
            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);
                selectedChannel = beam.SelectedChannel;
                destinationUTId = beam.AssociatedUTId;
                dataPackets{beamIndex} = Packet(PacketType.DATA, NodeType.Satellite, Satellite.Id, NodeType.UT, destinationUTId, beam.Id, ChannelType.Service, selectedChannel);
            end
            for beamIndex = 1:numel(dataPackets)
                packet = dataPackets{beamIndex};
                selectedChannel = packet.ChannelId;
                ServiceChannels(selectedChannel).addPacket(packet);
            end

            %% 4. UT의  현재 RF 환경 sensing
            for utIndex = 1:numel(UTs)
                UTs(utIndex).ObservationManager.observe(ServiceChannels, Satellite);
            end

     

            %% 5. UT의 HARQ 수행
            harqResults = cell(1, numel(UTs));
            sinrResults_dB = zeros(1, numel(UTs));
            for utIndex = 1:numel(UTs)
                [packetType, SINR_dB] = UTs(utIndex).performHARQ(ServiceChannels, ControlChannels, Satellite);
                harqResults{utIndex} = packetType;
                sinrResults_dB(utIndex) = SINR_dB;
            end

            %% 6. Beam이 UT feedback 수신 및 reward 저장
            actualACK = false(1, numel(Satellite.Beams));
            for beamIndex = 1:numel(Satellite.Beams)
                beam = Satellite.Beams(beamIndex);
                actualACK(beamIndex) = beam.receiveFeedback(ControlChannels, Satellite);
                beam.Agent.setReward(actualACK(beamIndex));
            end

            %% 7. APJ 동작
            %% 7.1 APJ의 현재 환경 sensing
            apjState = APJ.StateManager.getState();
            predictionForCurrentSlot = APJ.PredictedChannel;

            apjOccupancy = zeros(1, numel(ServiceChannels)); % Target Beam 1은 항상 첫 번째 선택자

            APJ.ObservationManager.observe(ServiceChannels, Satellite); % APJ 위치에서 RF sensing

            % Target Beam 실제 사용 채널 관측
            observedChannel = APJ.findObservedChannel(ServiceChannels);

            if ~isempty(predictionForCurrentSlot) && ~isempty(observedChannel)
                DebugHelper.recordAPJPrediction(slotIndex, predictionForCurrentSlot, observedChannel);
            end
            
            APJ.ObservationManager.observe(ServiceChannels, Satellite);
            estimatedTargetSINR_dB = APJ.estimateTargetSINR(ServiceChannels, Satellite);
            pseudoTargetACK = [];

            oracleObservation = UTs(1).ObservationManager.getCurrentObservation();
            actualTargetHARQ = harqResults{1};
            actualTargetACK = (actualTargetHARQ == PacketType.ACK);
            

            if ~isempty(observedChannel) && ~isempty(estimatedTargetSINR_dB)
                pseudoHARQ = APJ.generatePseudoHARQ(estimatedTargetSINR_dB);
                pseudoTargetACK = (pseudoHARQ == PacketType.ACK);


             %% 7.2 Oracle 정보 확보
                APJ.Agent.observeAction(apjState, apjOccupancy, observedChannel);
                APJ.Agent.setReward(actualTargetACK);


                % APJ StateManager 업데이트
                APJ.StateManager.update(oracleObservation, observedChannel, actualTargetHARQ);
                apjNextState = APJ.StateManager.getState();
                APJ.Agent.setCurrentState(apjNextState);
                APJ.Agent.setCurrentOccupancy(zeros(1, numel(ServiceChannels)));
                APJ.Agent.completeTransition();
    
                [apjLossValue, apjTrainingInfo] = APJ.Agent.train();

                [predictedChannel, apjQValues] = APJ.Agent.predictAction(apjNextState, zeros(1, numel(ServiceChannels)));
                APJ.PredictedChannel = predictedChannel;
                DebugHelper.printAPJTraining(APJ, slotIndex, observedChannel, estimatedTargetSINR_dB, pseudoHARQ, apjLossValue, apjTrainingInfo, apjQValues);
                % DebugHelper.printAPJPredictionQValues(slotIndex, predictedChannel, apjQValues);

            end



           

            %% 7.3 APJ Jamming
            if slotIndex > obj.ReconnaissanceDuration && ~isempty(APJ.PredictedChannel)
                APJ.JammingChannel = predictionForCurrentSlot;


                % 이후 여기서 Jamming Packet 생성 및
            
                % ServiceChannels(APJ.JammingChannel)에 삽입
            end



            



            %% 결과 반환
            actualTargetACK = (harqResults{1} == PacketType.ACK);
            %=============================================================
            % FigureHelper.plotBeam1SuccessRate(slotIndex, actualTargetACK);
            %=============================================================
            numACK = 0;
            for utIndex = 1:numel(UTs)
                if harqResults{utIndex} == PacketType.ACK
                    numACK = numACK + 1;
                end
            end
            successRatio = numACK / numel(UTs);
            %=============================================================
            % FigureHelper.plotSuccessRate(slotIndex, successRatio, 'All UTs (Aggregate)');
            %=============================================================
        end

        %% 채널 초기화
        function clearChannels(obj, ServiceChannels, ControlChannels)
            for channelIndex = 1:numel(ServiceChannels)
                ServiceChannels(channelIndex).clearPacket();
            end
            for channelIndex = 1:numel(ControlChannels)
                ControlChannels(channelIndex).clearPacket();
            end
        end
    end
end