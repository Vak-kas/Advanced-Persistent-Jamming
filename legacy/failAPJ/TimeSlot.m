classdef TimeSlot
    properties
        ReconnaissanceDuration
        % BeamLearnRate
    end
    methods
        function obj = TimeSlot()
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

            %% 4. APJ 동작
            %% 4.1 APJ의 현재 환경 sensing
            apjState = APJ.StateManager.getState();
            predictionForCurrentSlot = APJ.PredictedChannel;
            qValuesForCurrentSlot = APJ.PredictedQValues;   % ← 지난 슬롯에 저장해둔 Top-K 평가용 전체 Q-vector

            apjOccupancy = zeros(1, numel(ServiceChannels)); % Target Beam 1은 항상 첫 번째 선택자


            % Target Beam 실제 사용 채널 관측
            observedChannel = APJ.findObservedChannel(ServiceChannels);
            if ~isempty(predictionForCurrentSlot) && ~isempty(observedChannel)
                DebugHelper.recordAPJPrediction(slotIndex, predictionForCurrentSlot, observedChannel);
            end

            % ===== Top-K 정확도 평가 (지난 슬롯 예측 Q-vector vs 이번 슬롯 실제 채널) =====
            if ~isempty(qValuesForCurrentSlot) && ~isempty(observedChannel)
                obj.recordTopKAccuracy(slotIndex, qValuesForCurrentSlot, observedChannel);
            end

            APJ.ObservationManager.observe(ServiceChannels, Satellite);
            estimatedTargetSINR_dB = APJ.estimateTargetSINR(ServiceChannels, Satellite);
            pseudoTargetACK = [];

            if ~isempty(observedChannel) && ~isempty(estimatedTargetSINR_dB)
                pseudoHARQ = APJ.generatePseudoHARQ(estimatedTargetSINR_dB);
                pseudoTargetACK = (pseudoHARQ == PacketType.ACK);


                 %% 4.2 Transition 완성 + 학습
                APJ.Agent.observeAction(apjState, apjOccupancy, observedChannel);
                APJ.Agent.setReward(pseudoTargetACK);
                % APJ StateManager 업데이트
                APJ.StateManager.update(APJ.ObservationManager.getCurrentObservation(), observedChannel, pseudoHARQ);
                apjNextState = APJ.StateManager.getState();
                APJ.Agent.setCurrentState(apjNextState);
                APJ.Agent.setCurrentOccupancy(zeros(1, numel(ServiceChannels)));
                APJ.Agent.completeTransition();

                [apjLossValue, apjTrainingInfo] = APJ.Agent.train();

                [predictedChannel, apjQValues] = APJ.Agent.predictAction(apjNextState, zeros(1, numel(ServiceChannels)));
                APJ.PredictedChannel = predictedChannel;
                APJ.PredictedQValues = apjQValues;   % ← 다음 슬롯 Top-K 평가를 위해 전체 벡터 보관
                DebugHelper.printAPJTraining(APJ, slotIndex, observedChannel, estimatedTargetSINR_dB, pseudoHARQ, apjLossValue, apjTrainingInfo, apjQValues);
                % DebugHelper.printAPJPredictionQValues(slotIndex, predictedChannel, apjQValues);

            end




            %% 4.3 APJ Jamming
            if slotIndex > obj.ReconnaissanceDuration && ~isempty(APJ.PredictedChannel)
                APJ.JammingChannel = predictionForCurrentSlot;


                % 이후 여기서 Jamming Packet 생성 및

                % ServiceChannels(APJ.JammingChannel)에 삽입
            end



            %% 5. UT의  현재 RF 환경 sensing
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

        %% ===== Top-1~4 정확도 기록 및 출력 =====
        % qValues: 지난 슬롯에 만든 예측 시점의 전체 채널별 점수(Q-value 또는 확률) 벡터
        % actualChannel: 이번 슬롯 Target이 실제로 고른 채널
        function recordTopKAccuracy(obj, slotIndex, qValues, actualChannel)
            persistent top1Count top2Count top3Count top4Count totalCount

            if isempty(totalCount)
                top1Count = 0;
                top2Count = 0;
                top3Count = 0;
                top4Count = 0;
                totalCount = 0;
            end

            qValues = qValues(:)';   % 1 x numChannels 형태로 통일
            [~, sortedChannels] = sort(qValues, 'descend');   % 1등부터 순위

            totalCount = totalCount + 1;

            if any(sortedChannels(1)   == actualChannel)
                top1Count = top1Count + 1;
            end
            if any(sortedChannels(1:min(2,numel(sortedChannels))) == actualChannel)
                top2Count = top2Count + 1;
            end
            if any(sortedChannels(1:min(3,numel(sortedChannels))) == actualChannel)
                top3Count = top3Count + 1;
            end
            if any(sortedChannels(1:min(4,numel(sortedChannels))) == actualChannel)
                top4Count = top4Count + 1;
            end

            fprintf("\n============================================================\n");
            fprintf("APJ Top-K Prediction Accuracy\n");
            fprintf("============================================================\n");
            fprintf("  Slot                     : %d\n", slotIndex);
            fprintf("  Total Samples             : %d\n", totalCount);
            fprintf("  Top-1 Accuracy            : %.2f %% (Random baseline: 10.00 %%)\n", 100*top1Count/totalCount);
            fprintf("  Top-2 Accuracy            : %.2f %% (Random baseline: 20.00 %%)\n", 100*top2Count/totalCount);
            fprintf("  Top-3 Accuracy            : %.2f %% (Random baseline: 30.00 %%)\n", 100*top3Count/totalCount);
            fprintf("  Top-4 Accuracy            : %.2f %% (Random baseline: 40.00 %%)\n", 100*top4Count/totalCount);
            fprintf("============================================================\n");
        end
    end
end