classdef DebugHelper
    methods (Static)

        % ============================================================
        % Time Slot 출력
        % ============================================================
        function printTimeSlot(slotIndex)

            fprintf("\n");
            fprintf("------------------------------------------------------------\n");
            fprintf("Time Slot %d\n", slotIndex);
            fprintf("------------------------------------------------------------\n");

        end


        %% ========== Agent Training 결과 출력 ==========
        function printAgentTraining(beam, lossValue, trainingInfo)

            fprintf("\n");
            fprintf("============================================================\n");
            fprintf("Agent Training - Beam %d\n", beam.Id);
            fprintf("============================================================\n");

            fprintf("  Replay Buffer Count      : %d / %d\n", ...
                beam.Agent.ReplayBuffer.Count, ...
                beam.Agent.ReplayBuffer.Capacity);

            fprintf("  Batch Size               : %d\n", ...
                beam.Agent.BatchSize);

            fprintf("  Training Step            : %d\n", ...
                beam.Agent.TrainingStep);

            fprintf("  Epsilon                  : %.6f\n", ...
                beam.Agent.Epsilon);


            fprintf("\n");
            fprintf("  [Training]\n");

            if isempty(lossValue)

                fprintf("    Status                 : SKIPPED\n");
                fprintf("    Reason                 : Replay Buffer not ready\n");

            else

                fprintf("    Status                 : EXECUTED\n");
                fprintf("    Loss                   : %.8f\n", lossValue);

                fprintf("    Mean Q-Value           : %.6f\n", ...
                    trainingInfo.MeanQValue);

                fprintf("    Max Q-Value            : %.6f\n", ...
                    trainingInfo.MaxQValue);

                fprintf("    Mean Target Q-Value    : %.6f\n", ...
                    trainingInfo.MeanTargetQValue);

            end


            currentState = beam.StateManager.getState();
            currentOccupancy = zeros(1, beam.Agent.NumActions);

            dlState = beam.Agent.convertStateToDLArray(currentState);
            dlOccupancy = beam.Agent.convertOccupancyToDLArray(currentOccupancy);

            dlQValues = predict( ...
                beam.Agent.QNetwork, ...
                dlState, ...
                dlOccupancy ...
            );

            qValues = extractdata(dlQValues);
            qValues = qValues(:);


            fprintf("\n");
            fprintf("  [Current Q-Values]\n");

            [~, greedyAction] = max(qValues);

            for channelIndex = 1:numel(qValues)

                fprintf("    CH %2d : %10.6f", ...
                    channelIndex, ...
                    qValues(channelIndex));

                if channelIndex == greedyAction
                    fprintf("  <-- Greedy");
                end

                fprintf("\n");

            end

            fprintf("============================================================\n");

        end


        %% ========== APJ 예측 정확도 기록 ==========
        function recordAPJPrediction(slotIndex, predictedChannel, actualChannel, numChannels)

            newData.slot = slotIndex;
            newData.predicted = predictedChannel;
            newData.actual = actualChannel;

            data = DebugHelper.APJPredictionStorage('add', newData);

            totalCount = numel(data.actual);

            isCorrect = (predictedChannel == actualChannel);

            cumulativeAccuracy = mean(data.predicted == data.actual);

            recentWindow = min(100, totalCount);
            recentPredicted = data.predicted(end-recentWindow+1:end);
            recentActual = data.actual(end-recentWindow+1:end);
            recentAccuracy = mean(recentPredicted == recentActual);

            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('APJ Channel Prediction Evaluation\n');
            fprintf('============================================================\n');

            fprintf('  Slot                     : %d\n', slotIndex);
            fprintf('  Predicted Channel        : %d\n', predictedChannel);
            fprintf('  Actual Channel           : %d\n', actualChannel);

            if isCorrect
                fprintf('  Result                   : HIT\n');
            else
                fprintf('  Result                   : MISS\n');
            end

            fprintf('  Cumulative Accuracy      : %.2f %%\n', cumulativeAccuracy * 100);
            fprintf('  Recent Accuracy (%d)     : %.2f %%\n', recentWindow, recentAccuracy * 100);
            fprintf('============================================================\n');

        end


        %% ========== APJ Prediction Storage ==========
        function data = APJPredictionStorage(action, newData)

            persistent storage

            if isempty(storage)
                storage.slots = [];
                storage.predicted = [];
                storage.actual = [];
            end

            switch action
                case 'add'
                    storage.slots(end+1) = newData.slot;
                    storage.predicted(end+1) = newData.predicted;
                    storage.actual(end+1) = newData.actual;

                case 'get'
                    % 아무 작업 없음

                case 'reset'
                    storage.slots = [];
                    storage.predicted = [];
                    storage.actual = [];
            end

            data = storage;

        end


        %% ========== SINR 계산 상세 출력 ==========
        function printSINRCalculation( ...
                utId, ...
                desiredBeamId, ...
                channelId, ...
                centerFrequency_Hz, ...
                bandwidth_Hz, ...
                satelliteDistance, ...
                desiredTxPower_dBm, ...
                desiredTxGain_dBi, ...
                rxGain_dBi, ...
                desiredPower_W, ...
                interferencePackets, ...
                interferenceGain_dBi, ...
                interferencePowerEach_W, ...
                interferencePower_W, ...
                jammingPackets, ...
                jammingDistance, ...
                jammerTxPower_dBm, ...
                jammerTxGain_dBi, ...
                jammingPowerEach_W, ...
                jammingPower_W, ...
                noisePower_W, ...
                SINR_dB, ...
                sinrThreshold_dB)

            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('SINR Calculation - UT %d\n', utId);
            fprintf('============================================================\n');

            fprintf('  Channel                  : %d\n', channelId);
            fprintf('  Center Frequency         : %.3f MHz\n', ...
                centerFrequency_Hz / 1e6);
            fprintf('  Bandwidth                : %.3f kHz\n', ...
                bandwidth_Hz / 1e3);

            fprintf('\n');

            fprintf('  [Desired Signal]\n');
            fprintf('    Beam ID                : %d\n', desiredBeamId);
            fprintf('    Satellite-UT Distance  : %.3f km\n', ...
                satelliteDistance / 1e3);
            fprintf('    Tx Power               : %.3f dBm\n', ...
                desiredTxPower_dBm);
            fprintf('    Tx Gain                : %.3f dBi\n', ...
                desiredTxGain_dBi);
            fprintf('    UT Rx Gain             : %.3f dBi\n', ...
                rxGain_dBi);

            fprintf('    Received Power         : %.6e W (%8.3f dBm)\n', ...
                desiredPower_W, ...
                DebugHelper.wattToDbm(desiredPower_W));

            fprintf('\n');


            fprintf('  [Co-channel Interference]\n');

            if isempty(interferencePackets)

                fprintf('    Interfering Beams      : None\n');

            else

                fprintf('    Number of Interferers  : %d\n', ...
                    numel(interferencePackets));

                for interferenceIndex = 1:numel(interferencePackets)

                    interferencePacket = ...
                        interferencePackets(interferenceIndex);

                    fprintf('    #%d Beam %-3d | Gain: %8.3f dBi | Power: %8.3f dBm\n', ...
                        interferenceIndex, ...
                        interferencePacket.BeamId, ...
                        interferenceGain_dBi(interferenceIndex), ...
                        DebugHelper.wattToDbm( ...
                            interferencePowerEach_W(interferenceIndex)));
                end
            end

            fprintf('    Total Interference     : %.6e W (%8.3f dBm)\n', ...
                interferencePower_W, ...
                DebugHelper.wattToDbm(interferencePower_W));

            fprintf('\n');


            fprintf('  [APJ Jamming]\n');

            if isempty(jammingPackets)

                fprintf('    Status                 : NONE\n');

            else

                fprintf('    Status                 : ACTIVE\n');
                fprintf('    Number of Jammers      : %d\n', ...
                    numel(jammingPackets));

                if ~isempty(jammingDistance)
                    fprintf('    APJ-UT Distance        : %.3f km\n', ...
                        jammingDistance / 1e3);
                end

                fprintf('    APJ Tx Power           : %.3f dBm\n', ...
                    jammerTxPower_dBm);

                fprintf('    APJ Tx Gain            : %.3f dBi\n', ...
                    jammerTxGain_dBi);

                for jammingIndex = 1:numel(jammingPackets)

                    fprintf('    #%d Received Jam Power : %.6e W (%8.3f dBm)\n', ...
                        jammingIndex, ...
                        jammingPowerEach_W(jammingIndex), ...
                        DebugHelper.wattToDbm( ...
                            jammingPowerEach_W(jammingIndex)));
                end

            end

            fprintf('    Total Jamming Power    : %.6e W (%8.3f dBm)\n', ...
                jammingPower_W, ...
                DebugHelper.wattToDbm(jammingPower_W));

            fprintf('\n');


            fprintf('  [Noise]\n');

            fprintf('    Noise Power            : %.6e W (%8.3f dBm)\n', ...
                noisePower_W, ...
                DebugHelper.wattToDbm(noisePower_W));

            fprintf('\n');


            fprintf('  [Result]\n');

            fprintf('    Desired Power          : %8.3f dBm\n', ...
                DebugHelper.wattToDbm(desiredPower_W));

            fprintf('    Interference Power     : %8.3f dBm\n', ...
                DebugHelper.wattToDbm(interferencePower_W));

            fprintf('    Jamming Power          : %8.3f dBm\n', ...
                DebugHelper.wattToDbm(jammingPower_W));

            fprintf('    Noise Power            : %8.3f dBm\n', ...
                DebugHelper.wattToDbm(noisePower_W));

            fprintf('    SINR                    : %8.3f dB\n', ...
                SINR_dB);

            fprintf('    SINR Threshold          : %8.3f dB\n', ...
                sinrThreshold_dB);

            if SINR_dB >= sinrThreshold_dB
                fprintf('    HARQ Result             : ACK\n');
            else
                fprintf('    HARQ Result             : NACK\n');
            end

            fprintf('============================================================\n');
        end


        %% ========== Watt -> dBm ==========
        function power_dBm = wattToDbm(power_W)

            if power_W <= 0
                power_dBm = -Inf;
            else
                power_dBm = 10 * log10(power_W) + 30;
            end

        end


        %% ========== Target UT HARQ 결과 기록 ==========
        function recordTargetUTOutcome(slotIndex, packetType, SINR_dB, reconnaissanceDuration)

            if isempty(packetType)
                return;
            end

            isACK = (packetType == PacketType.ACK);

            newData.slot = slotIndex;
            newData.isACK = isACK;
            newData.SINR_dB = SINR_dB;
            newData.isAttackPhase = (slotIndex > reconnaissanceDuration);

            DebugHelper.TargetUTStorage('add', newData);

        end


        %% ========== Target UT Outcome Storage ==========
        function data = TargetUTStorage(action, newData)

            persistent storage

            if isempty(storage)
                storage.slots = [];
                storage.isACK = [];
                storage.SINR_dB = [];
                storage.isAttackPhase = [];
            end

            switch action
                case 'add'
                    storage.slots(end+1) = newData.slot;
                    storage.isACK(end+1) = newData.isACK;
                    storage.SINR_dB(end+1) = newData.SINR_dB;
                    storage.isAttackPhase(end+1) = newData.isAttackPhase;

                case 'get'
                    % 아무 작업 없음

                case 'reset'
                    storage.slots = [];
                    storage.isACK = [];
                    storage.SINR_dB = [];
                    storage.isAttackPhase = [];
            end

            data = storage;

        end


        %% ========== Target UT 정찰/공격 구간 비교 Summary ==========
        function printTargetUTSummary()

            data = DebugHelper.TargetUTStorage('get', []);

            if isempty(data.slots)
                fprintf('기록된 Target UT 데이터가 없습니다.\n');
                return;
            end

            attackIdx = logical(data.isAttackPhase);
            reconIdx = ~attackIdx;
            isACK = logical(data.isACK);

            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('TARGET UT THROUGHPUT SUMMARY (Reconnaissance vs Attack)\n');
            fprintf('============================================================\n');

            fprintf('  Total Slots               : %d\n', numel(data.slots));
            fprintf('  Reconnaissance Slots      : %d\n', sum(reconIdx));
            fprintf('  Attack Slots              : %d\n', sum(attackIdx));

            fprintf('\n');
            fprintf('  [ACK Rate]\n');
            fprintf('    Reconnaissance Phase   : %.2f %%\n', mean(isACK(reconIdx)) * 100);

            if any(attackIdx)
                fprintf('    Attack Phase           : %.2f %%\n', mean(isACK(attackIdx)) * 100);
            else
                fprintf('    Attack Phase           : N/A (no attack slots yet)\n');
            end

            fprintf('\n');
            fprintf('  [Mean SINR]\n');
            fprintf('    Reconnaissance Phase   : %.3f dB\n', mean(data.SINR_dB(reconIdx)));

            if any(attackIdx)
                fprintf('    Attack Phase           : %.3f dB\n', mean(data.SINR_dB(attackIdx)));
            else
                fprintf('    Attack Phase           : N/A\n');
            end

            fprintf('============================================================\n');

        end


        %% ========== Target UT ACK Rate 추이 그래프 ==========
        function plotTargetUTThroughput(windowSize)

            if nargin < 1
                windowSize = 100;
            end

            data = DebugHelper.TargetUTStorage('get', []);

            if isempty(data.slots)
                fprintf('기록된 Target UT 데이터가 없습니다.\n');
                return;
            end

            slots = data.slots;
            ackHistory = double(data.isACK);
            attackPhase = logical(data.isAttackPhase);

            rollingACKRate = movmean(ackHistory, [windowSize-1, 0]);
            cumulativeACKRate = cumsum(ackHistory) ./ (1:numel(ackHistory));

            attackStartIdx = find(attackPhase, 1);

            figure;

            subplot(2,1,1);
            plot(slots, cumulativeACKRate * 100, 'LineWidth', 1.2);
            hold on;
            plot(slots, rollingACKRate * 100, 'LineWidth', 1.2);
            if ~isempty(attackStartIdx)
                xline(slots(attackStartIdx), '--r', 'Attack Start', 'LineWidth', 1.2);
            end
            hold off;
            xlabel('Time Slot');
            ylabel('ACK Rate (%)');
            title('Target UT ACK Rate over Time');
            legend('Cumulative', sprintf('Rolling (window=%d)', windowSize), 'Location', 'southwest');
            grid on;
            ylim([0 100]);

            subplot(2,1,2);
            rollingSINR = movmean(data.SINR_dB, [windowSize-1, 0]);
            plot(slots, rollingSINR, 'LineWidth', 1.2);
            hold on;
            if ~isempty(attackStartIdx)
                xline(slots(attackStartIdx), '--r', 'Attack Start', 'LineWidth', 1.2);
            end
            hold off;
            xlabel('Time Slot');
            ylabel('SINR (dB)');
            title(sprintf('Target UT SINR over Time (Rolling window=%d)', windowSize));
            grid on;

        end


        %% ========== APJ Channel Prediction 최종 Summary ==========
        function printAPJPredictionSummary(numChannels)

            data = DebugHelper.APJPredictionStorage('get', []);

            predicted = data.predicted;
            actual = data.actual;
            slots = data.slots;

            totalCount = numel(actual);

            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('APJ CHANNEL PREDICTION SUMMARY\n');
            fprintf('============================================================\n');

            if totalCount == 0
                fprintf('  No prediction samples recorded.\n');
                fprintf('============================================================\n');
                return;
            end

            correctCount = sum(predicted == actual);
            incorrectCount = totalCount - correctCount;
            accuracy = correctCount / totalCount;
            randomBaseline = 1 / numChannels;

            fprintf('  Number of Channels       : %d\n', numChannels);
            fprintf('  Prediction Samples       : %d\n', totalCount);
            fprintf('  First Evaluated Slot     : %d\n', slots(1));
            fprintf('  Last Evaluated Slot      : %d\n', slots(end));

            fprintf('\n');
            fprintf('  [Overall Prediction Performance]\n');
            fprintf('    Correct Predictions    : %d\n', correctCount);
            fprintf('    Wrong Predictions      : %d\n', incorrectCount);
            fprintf('    Accuracy               : %6.2f %%\n', accuracy * 100);
            fprintf('    Random Baseline        : %6.2f %%\n', randomBaseline * 100);
            fprintf('    Improvement over Random: %6.2f x\n', accuracy / randomBaseline);

            recentWindow = min(100, totalCount);
            recentPredicted = predicted(end-recentWindow+1:end);
            recentActual = actual(end-recentWindow+1:end);
            recentAccuracy = mean(recentPredicted == recentActual);

            fprintf('\n');
            fprintf('  [Recent Performance]\n');
            fprintf('    Window Size            : %d\n', recentWindow);
            fprintf('    Accuracy               : %6.2f %%\n', recentAccuracy * 100);

            fprintf('\n');
            fprintf('  [Per-Channel Prediction Performance]\n');

            for ch = 1:numChannels
                actualCount = sum(actual == ch);
                predictedCount = sum(predicted == ch);
                correctChannelCount = sum((predicted == ch) & (actual == ch));

                if actualCount > 0
                    channelRecall = correctChannelCount / actualCount;
                    fprintf(['    CH %2d | Actual: %4d | Predicted: %4d | ' ...
                        'Correct: %4d | Recall: %6.2f %%\n'], ...
                        ch, actualCount, predictedCount, correctChannelCount, channelRecall * 100);
                else
                    fprintf(['    CH %2d | Actual: %4d | Predicted: %4d | ' ...
                        'Correct: %4d | Recall:   N/A\n'], ...
                        ch, actualCount, predictedCount, correctChannelCount);
                end
            end

            fprintf('============================================================\n');

        end


        %% ========== APJ Prediction Accuracy 추이 그래프 ==========
        function plotAPJAccuracyTrend(windowSize)

            if nargin < 1
                windowSize = 100;
            end

            data = DebugHelper.APJPredictionStorage('get', []);

            predicted = data.predicted;
            actual = data.actual;
            slots = data.slots;

            if isempty(slots)
                fprintf('기록된 예측 데이터가 없습니다.\n');
                return;
            end

            correctHistory = double(predicted == actual);

            cumulativeAccuracy = cumsum(correctHistory) ./ (1:numel(correctHistory));
            rollingAccuracy = movmean(correctHistory, [windowSize-1, 0]);

            figure;
            plot(slots, cumulativeAccuracy * 100, 'LineWidth', 1.2);
            hold on;
            plot(slots, rollingAccuracy * 100, 'LineWidth', 1.2);
            yline(100 / max(actual), '--', 'Random Baseline');
            hold off;

            xlabel('Time Slot');
            ylabel('Accuracy (%)');
            title('APJ Channel Prediction Accuracy over Time');
            legend('Cumulative Accuracy', sprintf('Rolling Accuracy (window=%d)', windowSize), 'Location', 'southeast');
            grid on;
            ylim([0 100]);

        end


        %% ========== APJ Prediction Storage 초기화 ==========
        function data = APJPredictionStorage_unused()
            data = [];
        end


        %% ========== Target Action Selection 출력 ==========
        function printTargetActionSelection(slotIndex, beam, selectedChannel, selectionMethod, randomValue, qValues)
            fprintf("\n============================================================\n");
            fprintf("TARGET ACTION SELECTION - SLOT %d\n", slotIndex);
            fprintf("============================================================\n");
            fprintf("  Selection Method         : %s\n", string(selectionMethod));
            fprintf("  Random Value             : %.8f\n", randomValue);
            fprintf("  Selected Channel         : %d\n", selectedChannel);
            fprintf("  Epsilon After Selection  : %.8f\n", beam.Agent.Epsilon);

            if isempty(qValues)
                fprintf("  Selection Q-values       : N/A (Random Action)\n");
            else
                qValuesDebug = double(qValues(:));
                [~, greedyChannel] = max(qValuesDebug);
                fprintf("\n  [Q-values used for Action Selection]\n");

                for channelIndex = 1:numel(qValuesDebug)
                    fprintf("    CH %2d : %+12.8f", channelIndex, qValuesDebug(channelIndex));

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
        end


        %% ========== Target UT vs APJ RF Observation 비교 ==========
        function printRFObservationComparison(slotIndex, targetUT, apjd, targetObservation, apjdObservation)
            targetPosition = double(targetUT.Position(:));
            apjdPosition = double(apjd.Position(:));
            distance_m = norm(targetPosition - apjdPosition);

            fprintf("\n============================================================\n");
            fprintf("TARGET UT vs APJ RF OBSERVATION - SLOT %d\n", slotIndex);
            fprintf("============================================================\n");
            fprintf("  Target UT ID             : %d\n", apjd.TargetUTId);

            if numel(targetPosition) >= 3
                fprintf("  Target UT Position       : (%+.3f, %+.3f, %+.3f) km\n", ...
                    targetPosition(1)/1e3, targetPosition(2)/1e3, targetPosition(3)/1e3);
            else
                fprintf("  Target UT Position       : (%+.3f, %+.3f) km\n", ...
                    targetPosition(1)/1e3, targetPosition(2)/1e3);
            end

            if numel(apjdPosition) >= 3
                fprintf("  APJ Position            : (%+.3f, %+.3f, %+.3f) km\n", ...
                    apjdPosition(1)/1e3, apjdPosition(2)/1e3, apjdPosition(3)/1e3);
            else
                fprintf("  APJ Position            : (%+.3f, %+.3f) km\n", ...
                    apjdPosition(1)/1e3, apjdPosition(2)/1e3);
            end

            fprintf("  APJ - Target UT Dist.   : %.6f km\n", distance_m/1e3);

            if isempty(targetObservation) || isempty(apjdObservation)
                fprintf("\n  Observation              : EMPTY\n");
                fprintf("============================================================\n");
                return;
            end

            targetObservation = double(targetObservation(:));
            apjdObservation = double(apjdObservation(:));

            if numel(targetObservation) ~= numel(apjdObservation)
                fprintf("\n  Observation Size Mismatch\n");
                fprintf("    Target count           : %d\n", numel(targetObservation));
                fprintf("    APJ count             : %d\n", numel(apjdObservation));
                fprintf("============================================================\n");
                return;
            end

            difference = targetObservation - apjdObservation;

            fprintf("\n  [Channel-wise RF Observation]\n");
            for channelIndex = 1:numel(targetObservation)
                fprintf("    CH %2d | UT1=%+12.6f dBm | APJ=%+12.6f dBm | SignedDiff=%+9.4f dB | AbsDiff=%8.4f dB\n", ...
                    channelIndex, targetObservation(channelIndex), apjdObservation(channelIndex), ...
                    difference(channelIndex), abs(difference(channelIndex)));
            end

            fprintf("\n");
            fprintf("  Target RF Min            : %.8f dBm\n", min(targetObservation));
            fprintf("  Target RF Max            : %.8f dBm\n", max(targetObservation));
            fprintf("  Target RF Mean           : %.8f dBm\n", mean(targetObservation));
            fprintf("  APJ RF Min              : %.8f dBm\n", min(apjdObservation));
            fprintf("  APJ RF Max              : %.8f dBm\n", max(apjdObservation));
            fprintf("  APJ RF Mean             : %.8f dBm\n", mean(apjdObservation));
            fprintf("  RF Observation L2 Diff  : %.8f\n", norm(difference));
            fprintf("  RF Mean Absolute Diff    : %.8f dB\n", mean(abs(difference)));
            fprintf("  RF Max Absolute Diff     : %.8f dB\n", max(abs(difference)));

            if std(targetObservation) > 0 && std(apjdObservation) > 0
                corrMatrix = corrcoef(targetObservation, apjdObservation);
                rfCorrelation = corrMatrix(1, 2);
            else
                rfCorrelation = NaN;
            end

            fprintf("  RF Pearson Correlation   : %.8f\n", rfCorrelation);
            fprintf("============================================================\n");
        end


        %% ========== RF Observation + Oracle Transition 비교 ==========
        function printRFOracleTransitionCheck(slotIndex, targetPrevState, targetPrevOccupancy, ...
                targetPrevAction, targetPrevReward, targetNextState, targetNextOccupancy, ...
                shadowPrevState, shadowPrevOccupancy, shadowPrevAction, shadowPrevReward, ...
                shadowNextState, shadowNextOccupancy)

            previousStateDiff = norm(double(targetPrevState(:)) - double(shadowPrevState(:)));
            previousOccupancyDiff = norm(double(targetPrevOccupancy(:)) - double(shadowPrevOccupancy(:)));
            actionMatch = targetPrevAction == shadowPrevAction;
            rewardMatch = targetPrevReward == shadowPrevReward;
            nextStateDiff = norm(double(targetNextState(:)) - double(shadowNextState(:)));
            nextOccupancyDiff = norm(double(targetNextOccupancy(:)) - double(shadowNextOccupancy(:)));

            fprintf("\n============================================================\n");
            fprintf("RF-OBSERVATION + ORACLE TRANSITION CHECK - SLOT %d\n", slotIndex);
            fprintf("============================================================\n");
            fprintf("  Previous State L2 Diff      : %.12f\n", previousStateDiff);
            fprintf("  Previous Occupancy Diff     : %.12f\n", previousOccupancyDiff);
            fprintf("  Previous Action Target      : %d\n", targetPrevAction);
            fprintf("  Previous Action Shadow      : %d\n", shadowPrevAction);
            fprintf("  Previous Action Match       : %s\n", DebugHelper.boolToString(actionMatch));
            fprintf("  Previous Reward Target      : %.8f\n", targetPrevReward);
            fprintf("  Previous Reward Shadow      : %.8f\n", shadowPrevReward);
            fprintf("  Previous Reward Match       : %s\n", DebugHelper.boolToString(rewardMatch));
            fprintf("  Next State L2 Diff          : %.12f\n", nextStateDiff);
            fprintf("  Next Occupancy Diff         : %.12f\n", nextOccupancyDiff);

            oracleComponentsMatch = previousOccupancyDiff == 0 && actionMatch && ...
                rewardMatch && nextOccupancyDiff == 0;

            fprintf("  Oracle Components Match     : %s\n", ...
                DebugHelper.boolToString(oracleComponentsMatch));

            if previousStateDiff > 0 || nextStateDiff > 0
                fprintf("  RF State Difference         : PRESENT (EXPECTED)\n");
            else
                fprintf("  RF State Difference         : ZERO\n");
            end

            fprintf("============================================================\n");
        end


        %% ========== Shadow DQN Training 출력 ==========
        function printShadowTraining(slotIndex, shadowAgent, state, occupancy, lossValue, trainingInfo)
            fprintf("\n============================================================\n");
            fprintf("APJ RF-SHADOW AGENT TRAINING - SLOT %d\n", slotIndex);
            fprintf("============================================================\n");
            fprintf("  Replay Buffer Count      : %d / %d\n", ...
                shadowAgent.ReplayBuffer.Count, shadowAgent.ReplayBuffer.Capacity);
            fprintf("  Batch Size               : %d\n", shadowAgent.BatchSize);
            fprintf("  Training Step            : %d\n", shadowAgent.TrainingStep);
            fprintf("  State Source             : APJ RF Observation\n");
            fprintf("  Occupancy Source         : ORACLE\n");
            fprintf("  Action Source            : ORACLE\n");
            fprintf("  Reward Source            : ORACLE\n");

            fprintf("\n  [Training]\n");
            if isempty(lossValue)
                fprintf("    Status                 : SKIPPED\n");
                fprintf("    Reason                 : Replay Buffer not ready\n");
            else
                fprintf("    Status                 : EXECUTED\n");
                fprintf("    Loss                   : %.8f\n", lossValue);
                fprintf("    Mean Q-Value           : %.8f\n", trainingInfo.MeanQValue);
                fprintf("    Max Q-Value            : %.8f\n", trainingInfo.MaxQValue);
                fprintf("    Mean Target Q-Value    : %.8f\n", trainingInfo.MeanTargetQValue);
            end

            dlState = shadowAgent.convertStateToDLArray(state);
            dlOccupancy = shadowAgent.convertOccupancyToDLArray(occupancy);
            dlQValues = predict(shadowAgent.QNetwork, dlState, dlOccupancy);
            qValues = double(extractdata(dlQValues));
            qValues = qValues(:);
            [maxQValue, greedyAction] = max(qValues);

            fprintf("\n  [Current Shadow Q-Values]\n");
            for channelIndex = 1:numel(qValues)
                fprintf("    CH %2d : %+12.8f", channelIndex, qValues(channelIndex));
                if channelIndex == greedyAction
                    fprintf("  <-- Greedy");
                end
                fprintf("\n");
            end

            fprintf("\n");
            fprintf("  Greedy Action            : CH%d\n", greedyAction);
            fprintf("  Max Q                    : %.8f\n", maxQValue);
            fprintf("  Q Range                  : %.8f\n", max(qValues) - min(qValues));
            fprintf("  Q Std                    : %.8f\n", std(qValues));
            fprintf("============================================================\n");
        end


        %% ========== Target vs Shadow Q 비교 ==========
        function printTargetVsShadowDQN(slotIndex, targetAction, qTarget, qShadow, ...
                greedyTarget, greedyShadow, qCosSim, qL2Dist, ...
                weightDiffNorm, weightNormTarget, weightNormShadow)

            fprintf("\n============================================================\n");
            fprintf("TARGET vs RF-SHADOW DQN - SLOT %d\n", slotIndex);
            fprintf("============================================================\n");
            fprintf("  Shadow State Source      : APJ RF Observation\n");
            fprintf("  Shadow Occupancy Source  : ORACLE\n");
            fprintf("  Shadow Action Source     : ORACLE\n");
            fprintf("  Shadow Reward Source     : ORACLE\n\n");
            fprintf("  Target Actual Action     : CH%d\n", targetAction);
            fprintf("  Target Greedy Action     : CH%d\n", greedyTarget);
            fprintf("  Shadow Greedy Prediction : CH%d\n", greedyShadow);

            fprintf("\n  [Q-value Comparison]\n");
            for channelIndex = 1:numel(qTarget)
                fprintf("    CH %2d | Target=%+11.7f | Shadow=%+11.7f | Diff=%10.7f", ...
                    channelIndex, qTarget(channelIndex), qShadow(channelIndex), ...
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
            fprintf("  Q Cosine Similarity      : %.8f\n", qCosSim);
            fprintf("  Q L2 Distance            : %.8f\n", qL2Dist);
            fprintf("  Argmax Match             : %d\n", double(greedyTarget == greedyShadow));
            fprintf("  Weight Diff L2 Norm      : %.8f\n", weightDiffNorm);
            fprintf("  Target Weight Norm       : %.8f\n", weightNormTarget);
            fprintf("  Shadow Weight Norm       : %.8f\n", weightNormShadow);
            fprintf("============================================================\n");
        end


        %% ========== Reward 결과 출력 ==========
        function printRewardResult(slotIndex, targetAction, targetPacketType, targetOutcome, targetAgent, shadowAgent)
            fprintf("\n============================================================\n");
            fprintf("REWARD RESULT - SLOT %d\n", slotIndex);
            fprintf("============================================================\n");
            fprintf("  Target Channel           : CH%d\n", targetAction);
            fprintf("  HARQ                     : %s\n", DebugHelper.packetTypeToString(targetPacketType));
            fprintf("  Target Outcome           : %d\n", targetOutcome);
            fprintf("  Reward Source            : ORACLE\n");
            fprintf("  Target Pending Reward    : %.8f\n", targetAgent.PendingReward);
            fprintf("  Shadow Pending Reward    : %.8f\n", shadowAgent.PendingReward);
            fprintf("============================================================\n");
        end


        %% ========== Boolean -> String ==========
        function text = boolToString(value)
            if value
                text = "YES";
            else
                text = "NO";
            end
        end


        %% ========== PacketType -> String ==========
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

                %% ========== IJ Agent Training 결과 출력 ==========
        function printIJTraining(ij, lossValue, trainingInfo)

            fprintf("\n");
            fprintf("============================================================\n");
            fprintf("IJ Agent Training - IJ %d\n", ij.Id);
            fprintf("============================================================\n");

            fprintf("  Replay Buffer Count      : %d / %d\n", ...
                ij.Agent.ReplayBuffer.Count, ...
                ij.Agent.ReplayBuffer.Capacity);

            fprintf("  Batch Size               : %d\n", ...
                ij.Agent.BatchSize);

            fprintf("  Training Step            : %d\n", ...
                ij.Agent.TrainingStep);

            fprintf("  Epsilon                  : %.6f\n", ...
                ij.Agent.Epsilon);


            fprintf("\n");
            fprintf("  [Training]\n");

            if isempty(lossValue)

                fprintf("    Status                 : SKIPPED\n");
                fprintf("    Reason                 : Replay Buffer not ready (Count < BatchSize)\n");

            else

                fprintf("    Status                 : EXECUTED\n");
                fprintf("    Loss                   : %.8f\n", lossValue);

                fprintf("    Mean Q-Value           : %.6f\n", ...
                    trainingInfo.MeanQValue);

                fprintf("    Max Q-Value            : %.6f\n", ...
                    trainingInfo.MaxQValue);

                fprintf("    Mean Target Q-Value    : %.6f\n", ...
                    trainingInfo.MeanTargetQValue);

            end

            fprintf("============================================================\n");

        end


        %% ========== IJ Action Selection (Top-K Q-value + 채널쌍 디코딩) 출력 ==========
        function printIJActionSelection(slotIndex, ij, actionIndex, selectionMethod, qValues, reward)

            fprintf("\n============================================================\n");
            fprintf("IJ ACTION SELECTION - SLOT %d\n", slotIndex);
            fprintf("============================================================\n");
            fprintf("  Selection Method         : %s\n", string(selectionMethod));
            fprintf("  Epsilon After Selection  : %.8f\n", ij.Agent.Epsilon);

            selectedChannels = ij.Agent.decodeAction(actionIndex);
            fprintf("  Selected Action Index    : %d / %d\n", actionIndex, ij.Agent.NumActions);
            fprintf("  Selected Channels        : %s\n", mat2str(selectedChannels));

            if ~isempty(reward)
                fprintf("  Last Reward (self-sensed): %.6f\n", reward);
            end

            if isempty(qValues)

                fprintf("  Selection Q-values       : N/A (Random Action)\n");

            else

                qValuesDebug = double(qValues(:));
                [sortedQ, sortedIdx] = sort(qValuesDebug, 'descend');
                topK = min(5, numel(sortedQ));

                fprintf("\n  [Top-%d Q-values]\n", topK);

                for rank = 1:topK

                    idx = sortedIdx(rank);
                    channels = ij.Agent.decodeAction(idx);

                    fprintf("    #%d  ActionIdx %3d  CH%s  Q=%+12.8f", ...
                        rank, idx, mat2str(channels), sortedQ(rank));

                    if idx == actionIndex
                        fprintf("  <-- Selected");
                    end

                    fprintf("\n");

                end

                fprintf("\n");
                fprintf("  Q Range                  : %.8f\n", max(qValuesDebug) - min(qValuesDebug));
                fprintf("  Q Std                    : %.8f\n", std(qValuesDebug));

            end

            fprintf("============================================================\n");

        end

    end
end