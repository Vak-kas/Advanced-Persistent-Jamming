classdef DebugHelper

    methods (Static)

        % ========== Time Slot 출력 ==========
        function printTimeSlot(slotIndex)

            fprintf("\n");
            fprintf("------------------------------------------------------------\n");
            fprintf("Time Slot %d\n", slotIndex);
            fprintf("------------------------------------------------------------\n");

        end


        % ========== UT-Satellite 거리 출력 ==========
        function printAssociationDistances(UTs, Satellites)

            fprintf("\n[UT-Satellite Distance]\n");

            for satelliteIndex = 1:numel(Satellites)

                utId = Satellites(satelliteIndex).AssociatedUTId;

                distance_m = ...
                    UTs(utId).distanceTo(Satellites(satelliteIndex));

                fprintf( ...
                    "  Satellite %2d - UT %2d | Distance: %.2f km\n", ...
                    Satellites(satelliteIndex).Id, ...
                    utId, ...
                    distance_m / 1e3);
            end

            fprintf("\n");
        end


        % ========== 채널 정보 출력 ==========
        function printChannels(ServiceChannels, ControlChannels)

            fprintf("\n[Channel Information]\n");

            fprintf("  Service Channels\n");

            for channelIndex = 1:numel(ServiceChannels)

                channel = ServiceChannels(channelIndex);
                packets = channel.getPackets();

                fprintf("    Channel %2d", channel.Id);

                if isempty(packets)
                    fprintf(" : Empty\n");
                    continue;
                end

                fprintf("\n");

                for packetIndex = 1:numel(packets)

                    packet = packets(packetIndex);

                    fprintf( ...
                        "      %s | %s %d -> %s %d\n", ...
                        char(string(packet.Type)), ...
                        char(string(packet.SourceType)), ...
                        packet.SourceId, ...
                        char(string(packet.DestinationType)), ...
                        packet.DestinationId);
                end
            end

            fprintf("\n");
            fprintf("  Control Channels\n");

            for channelIndex = 1:numel(ControlChannels)

                channel = ControlChannels(channelIndex);
                packets = channel.getPackets();

                fprintf("    Channel %2d", channel.Id);

                if isempty(packets)
                    fprintf(" : Empty\n");
                    continue;
                end

                fprintf("\n");

                for packetIndex = 1:numel(packets)

                    packet = packets(packetIndex);

                    fprintf( ...
                        "      %s | %s %d -> %s %d\n", ...
                        char(string(packet.Type)), ...
                        char(string(packet.SourceType)), ...
                        packet.SourceId, ...
                        char(string(packet.DestinationType)), ...
                        packet.DestinationId);
                end
            end

            fprintf("\n");
        end


        % ========== SINR 출력 ==========
        function printSINR( ...
                satelliteId, ...
                targetUTId, ...
                channelId, ...
                distance_m, ...
                receivedPower_W, ...
                interferencePower_W, ...
                noisePower_W, ...
                SINR_linear, ...
                SINR_dB, ...
                threshold_dB)

            receivedPower_dBm = ...
                DebugHelper.wattToDbm(receivedPower_W);

            noisePower_dBm = ...
                DebugHelper.wattToDbm(noisePower_W);

            if interferencePower_W > 0
                interferencePower_dBm = ...
                    DebugHelper.wattToDbm(interferencePower_W);
            else
                interferencePower_dBm = -Inf;
            end

            if SINR_dB >= threshold_dB
                result = "ACK";
            else
                result = "NACK";
            end

            fprintf("\n[SINR Debug | Satellite %d, UT %d]\n", ...
                satelliteId, targetUTId);

            fprintf("  Channel            : %d\n", channelId);
            fprintf("  Distance           : %.2f km\n", ...
                distance_m / 1e3);

            fprintf("  Desired Power      : %.4e W | %.4f dBm\n", ...
                receivedPower_W, receivedPower_dBm);

            if interferencePower_W > 0
                fprintf("  Interference Power : %.4e W | %.4f dBm\n", ...
                    interferencePower_W, interferencePower_dBm);
            else
                fprintf("  Interference Power : 0 W | -Inf dBm\n");
            end

            fprintf("  Noise Power        : %.4e W | %.4f dBm\n", ...
                noisePower_W, noisePower_dBm);

            fprintf("  SINR Linear        : %.4e\n", SINR_linear);
            fprintf("  SINR               : %.4f dB\n", SINR_dB);
            fprintf("  Threshold          : %.4f dB\n", threshold_dB);
            fprintf("  HARQ Result        : %s\n", char(result));

            fprintf("\n");
        end


        % ========== W -> dBm 변환 ==========
        function power_dBm = wattToDbm(power_W)

            if power_W > 0
                power_dBm = 10 * log10(power_W) + 30;
            else
                power_dBm = -Inf;
            end

        end


        % ========== APJ HARQ 예측 결과 출력 ==========
        function printHARQPredictionResult(TP, FN, FP, TN)

            total = TP + TN + FP + FN;

            if total == 0
                accuracy = 0;
            else
                accuracy = (TP + TN) / total;
            end

            if (TP + FP) == 0
                precision = 0;
            else
                precision = TP / (TP + FP);
            end

            if (TP + FN) == 0
                recall = 0;
            else
                recall = TP / (TP + FN);
            end

            if (precision + recall) == 0
                f1Score = 0;
            else
                f1Score = ...
                    2 * precision * recall / (precision + recall);
            end

            fprintf("\n");
            fprintf("------------------------------------------------------------\n");
            fprintf("APJ HARQ Prediction Result\n");
            fprintf("------------------------------------------------------------\n");

            fprintf("  TP        : %d\n", TP);
            fprintf("  FN        : %d\n", FN);
            fprintf("  FP        : %d\n", FP);
            fprintf("  TN        : %d\n", TN);

            fprintf("\n");

            fprintf("  Accuracy  : %.4f\n", accuracy);
            fprintf("  Precision : %.4f\n", precision);
            fprintf("  Recall    : %.4f\n", recall);
            fprintf("  F1 Score  : %.4f\n", f1Score);

            fprintf("------------------------------------------------------------\n");
        end


        % ========== Satellite 정보 출력 ==========
        function printSatelliteInfo(satellite)

            fprintf("\n[Satellite %d Information]\n", satellite.Id);

            fprintf("  Rx Gain            : %.1f dBi\n", ...
                satellite.SatelliteRxGain_dBi);

            fprintf("  G/T                : %.1f dB/K\n", ...
                satellite.SatelliteGOverT_dB);

            fprintf("  System Noise Temp. : %.2f K\n", ...
                satellite.SystemNoiseTemperature_K);

            fprintf("  Tx Power           : %.2f dBm\n", ...
                satellite.TxPower_dBm);

            fprintf("  Associated UT      : %d\n", ...
                satellite.AssociatedUTId);

            fprintf("  SINR Threshold     : %.2f dB\n", ...
                satellite.Threshold);

            fprintf("  Position           : (%.2f, %.2f, %.2f) m\n", ...
                satellite.Position(1), ...
                satellite.Position(2), ...
                satellite.Position(3));

            fprintf("\n");
        end


        % ========== 채널 센싱 출력 ==========
        function printObservation(owner, ServiceChannels, UTs)

            fprintf("\n[Observation | UT %d]\n", owner.Id);

            for channelIndex = 1:numel(ServiceChannels)

                channel = ServiceChannels(channelIndex);
                packets = channel.getPackets();

                totalSignalPower_W = 0;
                signalCount = 0;

                fprintf("  Channel %2d\n", channel.Id);

                for packetIndex = 1:numel(packets)

                    packet = packets(packetIndex);

                    % 자신의 송신 신호 제외
                    if packet.SourceId == owner.Id && ...
                            packet.SourceType == owner.Type
                        continue;
                    end

                    if owner.Type == NodeType.APJ && ...
                       packet.SourceType == NodeType.UT && ...
                       packet.SourceId == owner.TargetUTId
                        continue;
                    end

                    sourceNode = UTs(packet.SourceId);

                    lambda = 3e8 / channel.CenterFrequency_Hz;
                    distance_m = owner.distanceTo(sourceNode);

                    channelGain = ...
                        (lambda / (4 * pi * distance_m))^2;

                    txPower_W = ...
                        10^((sourceNode.TxPower_dBm - 30) / 10);

                    rxPower_W = txPower_W * channelGain;
                    rxPower_dBm = DebugHelper.wattToDbm(rxPower_W);

                    totalSignalPower_W = ...
                        totalSignalPower_W + rxPower_W;

                    signalCount = signalCount + 1;

                    fprintf( ...
                        "    UT %2d | Distance: %6.2f km | Rx: %8.2f dBm\n", ...
                        packet.SourceId, ...
                        distance_m / 1e3, ...
                        rxPower_dBm);
                end

                noiseFactor = ...
                    10^(owner.NoiseFigure_dB / 10);

                noisePower_W = ...
                    owner.k * ...
                    owner.NoiseTemperature * ...
                    channel.Bandwidth_Hz * ...
                    noiseFactor;

                noisePower_dBm = ...
                    DebugHelper.wattToDbm(noisePower_W);

                totalPower_W = ...
                    totalSignalPower_W + noisePower_W;

                totalPower_dBm = ...
                    DebugHelper.wattToDbm(totalPower_W);

                if signalCount == 0
                    fprintf("    Signal : None\n");
                end

                fprintf("    Noise  : %.2f dBm\n", noisePower_dBm);
                fprintf("    Total  : %.2f dBm\n", totalPower_dBm);
            end

            fprintf("\n");
        end


        % ========== UT 채널 선택 과정 출력 ==========
        function printUTActionSelection( ...
                ownerId, ...
                selectionMethod, ...
                epsilon, ...
                randomValue, ...
                action, ...
                qValues)

            fprintf("\n[Action Selection | UT %d]\n", ownerId);

            fprintf("  Method           : %s\n", ...
                char(selectionMethod));

            fprintf("  Epsilon          : %.6f\n", epsilon);
            fprintf("  Random Value     : %.6f\n", randomValue);
            fprintf("  Selected Channel : %d\n", action);

            if strcmp(selectionMethod, "DQN")

                fprintf("\n");
                fprintf("  Q-values\n");

                for channelIndex = 1:numel(qValues)

                    fprintf("    Ch %2d : %9.4f\n", ...
                        channelIndex, ...
                        qValues(channelIndex));
                end

                [maxQValue, maxChannel] = max(qValues);

                fprintf("\n");
                fprintf("  Best Channel     : %d\n", maxChannel);
                fprintf("  Maximum Q-value  : %.6f\n", maxQValue);
            end

            fprintf("\n");
        end


        % ========== Reward 출력 ==========
        function printReward(ownerId, reward, isACK)
            fprintf("\n[Reward | UT %d]\n", ownerId);
            if isACK
                fprintf("  HARQ Result      : ACK\n");
            else
                fprintf("  HARQ Result      : NACK\n");
            end
            fprintf("  Reward           : %.2f\n", reward);
            fprintf("\n");
        end

        % ========== DQN 학습 결과 출력 ==========
        function printTraining(ownerId, replayCount, trainingStep, lossValue)
        
            fprintf("\n[Training | UT %d]\n", ownerId);
            fprintf("  Replay Count  : %d\n", replayCount);
            fprintf("  Training Step : %d\n", trainingStep);
            fprintf("  Loss          : %.6f\n", lossValue);
            fprintf("\n");
        end


        % ========== APJ Shadowing 결과 출력 ========== %
        function printAPJShadowing( ...
            slotIndex, ...
            actualChannel, ...
            utGreedyChannel, ...
            predictedChannel, ...
            utQValues, ...
            apjQValues)
        
            % 실제 Action 예측 성공 여부
            actualPredictionCorrect = ...
                (predictedChannel == actualChannel);
        
            % Greedy Policy 일치 여부
            greedyAgreement = ...
                (predictedChannel == utGreedyChannel);
        
            fprintf("\n");
            fprintf("------------------------------------------------------------\n");
            fprintf("APJ Shadowing | Slot %d\n", slotIndex);
            fprintf("------------------------------------------------------------\n");
        
            fprintf("  Actual UT Channel     : %d\n", actualChannel);
            fprintf("  UT Greedy Channel     : %d\n", utGreedyChannel);
            fprintf("  APJ Predicted Channel : %d\n", predictedChannel);
        
            fprintf("\n");
        
            if actualPredictionCorrect
                fprintf("  Actual Prediction     : Correct\n");
            else
                fprintf("  Actual Prediction     : Wrong\n");
            end
        
            if greedyAgreement
                fprintf("  Greedy Agreement      : Correct\n");
            else
                fprintf("  Greedy Agreement      : Wrong\n");
            end
        
        
            % UT Q-values
            fprintf("\n");
            fprintf("  UT Q-values\n");
        
            for channelIndex = 1:numel(utQValues)
                fprintf( ...
                    "    Ch %2d : %10.4f\n", ...
                    channelIndex, ...
                    utQValues(channelIndex));
            end
        
        
            % APJ Q-values
            fprintf("\n");
            fprintf("  APJ Q-values\n");
        
            for channelIndex = 1:numel(apjQValues)
                fprintf( ...
                    "    Ch %2d : %10.4f\n", ...
                    channelIndex, ...
                    apjQValues(channelIndex));
            end
        
            fprintf("------------------------------------------------------------\n");
        end

    end

end