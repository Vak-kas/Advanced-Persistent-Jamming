classdef DebugHelper
    methods (Static)

        % ============================================================
        % Satellite 정보 출력
        % ============================================================
        function printSatelliteInfo(SatelliteNode)

            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('Satellite Information\n');
            fprintf('============================================================\n');

            fprintf('  Satellite ID       : %d\n', SatelliteNode.Id);

            fprintf('  Position           : (%.2f, %.2f, %.2f) km\n', ...
                SatelliteNode.Position(1)/1e3, ...
                SatelliteNode.Position(2)/1e3, ...
                SatelliteNode.Position(3)/1e3);

            fprintf('  Number of Beams    : %d\n', ...
                numel(SatelliteNode.Beams));

            fprintf('============================================================\n');


            fprintf('\n');
            fprintf('------------------------------------------------------------\n');
            fprintf('Associated Beam Information\n');
            fprintf('------------------------------------------------------------\n');

            for beamIndex = 1:numel(SatelliteNode.Beams)

                beam = SatelliteNode.Beams(beamIndex);

                fprintf('\n');
                fprintf('  [Beam %d]\n', beam.Id);

                fprintf('    Center Position       : (%.2f, %.2f, %.2f) km\n', ...
                    beam.CenterPosition(1)/1e3, ...
                    beam.CenterPosition(2)/1e3, ...
                    beam.CenterPosition(3)/1e3);

                fprintf('    Radius                : %.2f km\n', ...
                    beam.Radius/1e3);

                fprintf('    Diameter              : %.2f km\n', ...
                    2 * beam.Radius/1e3);

                fprintf('    Max Tx Gain           : %.2f dBi\n', ...
                    beam.MaxTxGain_dBi);

                fprintf('    3 dB Beamwidth        : %.4f deg\n', ...
                    beam.Beamwidth3dB_deg);

                fprintf('    Tx Power              : %.2f dBm\n', ...
                    beam.TxPower_dBm);

                fprintf('    Associated UT ID      : %d\n', ...
                    beam.AssociatedUTId);

                fprintf('    Selected Channel      : %d\n', ...
                    beam.SelectedChannel);

            end

            fprintf('\n');
            fprintf('============================================================\n');

        end


        % ============================================================
        % UT 정보 출력
        % ============================================================
        function printUTInfo(UTs, Beams, SatelliteNode)

            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('UT Information\n');
            fprintf('============================================================\n');

            satellitePosition = SatelliteNode.Position(:);

            satelliteGroundPosition = satellitePosition;
            satelliteGroundPosition(3) = 0;


            for utIndex = 1:numel(UTs)

                ut = UTs(utIndex);
                beam = Beams(ut.AssociatedBeamId);

                utPosition = ut.Position(:);

                % Beam 중심 ↔ UT
                beamCenterDistance = ...
                    beam.groundDistanceTo(utPosition);

                % Satellite ↔ UT 실제 3D 거리
                satelliteDistance = ...
                    norm(satellitePosition - utPosition);

                % Satellite 직하점 ↔ UT 지상거리
                satelliteGroundDistance = ...
                    norm( ...
                        satelliteGroundPosition(1:2) ...
                        - utPosition(1:2) ...
                    );


                fprintf('\n');
                fprintf('  [UT %d]\n', ut.Id);

                fprintf('    Position                    : (%.2f, %.2f, %.2f) km\n', ...
                    ut.Position(1)/1e3, ...
                    ut.Position(2)/1e3, ...
                    ut.Position(3)/1e3);

                fprintf('    Target UT                   : %s\n', ...
                    DebugHelper.boolToString(ut.IsTarget));

                fprintf('    Associated Beam ID          : %d\n', ...
                    ut.AssociatedBeamId);

                fprintf('    Associated Beam Center      : (%.2f, %.2f, %.2f) km\n', ...
                    beam.CenterPosition(1)/1e3, ...
                    beam.CenterPosition(2)/1e3, ...
                    beam.CenterPosition(3)/1e3);

                fprintf('    Beam Center Distance        : %.2f km\n', ...
                    beamCenterDistance/1e3);

                fprintf('    Beam Radius                 : %.2f km\n', ...
                    beam.Radius/1e3);

                fprintf('    Satellite Distance          : %.2f km\n', ...
                    satelliteDistance/1e3);

                fprintf('    Satellite Ground Distance   : %.2f km\n', ...
                    satelliteGroundDistance/1e3);

                fprintf('    Tx Power                    : %.2f dBm\n', ...
                    ut.TxPower_dBm);

                fprintf('    Rx Gain                     : %.2f dBi\n', ...
                    ut.RxGain_dBi);

                fprintf('    Noise Temperature           : %.2f K\n', ...
                    ut.NoiseTemperature);

                fprintf('    Noise Figure                : %.2f dB\n', ...
                    ut.NoiseFigure_dB);

                fprintf('    SINR Threshold              : %.2f dB\n', ...
                    ut.SINRThreshold_dB);

            end

            fprintf('\n');
            fprintf('============================================================\n');

        end


        % ============================================================
        % APJ 정보 출력
        % ============================================================
        function printAPJInfo(APJNode, UTs, SatelliteNode)

            targetUT = UTs(APJNode.TargetUTId);

            apjPosition = APJNode.Position(:);
            targetPosition = targetUT.Position(:);
            satellitePosition = SatelliteNode.Position(:);

            % APJ ↔ Target UT 지상거리
            targetUTDistance = norm( ...
                apjPosition(1:2) - targetPosition(1:2) ...
            );

            % APJ ↔ Satellite 3D 거리
            satelliteDistance = norm( ...
                apjPosition - satellitePosition ...
            );

            % Satellite 직하점 ↔ APJ
            satelliteGroundDistance = norm( ...
                apjPosition(1:2) - satellitePosition(1:2) ...
            );


            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('APJ Information\n');
            fprintf('============================================================\n');

            fprintf('  APJ ID                     : %d\n', ...
                APJNode.Id);

            fprintf('  Position                   : (%.2f, %.2f, %.2f) km\n', ...
                APJNode.Position(1)/1e3, ...
                APJNode.Position(2)/1e3, ...
                APJNode.Position(3)/1e3);

            fprintf('  Target UT ID               : %d\n', ...
                APJNode.TargetUTId);

            fprintf('  Target UT Distance         : %.2f km\n', ...
                targetUTDistance/1e3);

            fprintf('  Satellite Distance         : %.2f km\n', ...
                satelliteDistance/1e3);

            fprintf('  Satellite Ground Distance  : %.2f km\n', ...
                satelliteGroundDistance/1e3);

            fprintf('  Tx Power                   : %.2f dBm\n', ...
                APJNode.TxPower_dBm);

            fprintf('  Rx Gain                    : %.2f dBi\n', ...
                APJNode.RxGain_dBi);

            fprintf('  Noise Temperature          : %.2f K\n', ...
                APJNode.NoiseTemperature);

            fprintf('  Noise Figure               : %.2f dB\n', ...
                APJNode.NoiseFigure_dB);

            fprintf('  SINR Threshold             : %.2f dB\n', ...
                APJNode.SINRThreshold_dB);

            fprintf('============================================================\n');

        end


        % ============================================================
        % Beam - UT Association 검사
        % ============================================================
        function printBeamUTAssociation(Beams, UTs)

            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('Beam - UT Association\n');
            fprintf('============================================================\n');

            for beamIndex = 1:numel(Beams)

                beam = Beams(beamIndex);
                ut = UTs(beam.AssociatedUTId);

                distance = beam.groundDistanceTo(ut.Position);

                fprintf( ...
                    '  Beam %2d <-> UT %2d | Distance: %6.2f km | ', ...
                    beam.Id, ...
                    ut.Id, ...
                    distance/1e3 ...
                );

                if distance <= beam.Radius
                    fprintf('Inside\n');
                else
                    fprintf('OUTSIDE\n');
                end

            end

            fprintf('============================================================\n');

        end


        % ============================================================
        % Boolean → String
        % ============================================================
        function result = boolToString(value)

            if value
                result = 'Yes';
            else
                result = 'No';
            end

        end

        % ============================================================
        % Time Slot 출력
        % ============================================================
        function printTimeSlot(slotIndex)

            fprintf("\n");
            fprintf("------------------------------------------------------------\n");
            fprintf("Time Slot %d\n", slotIndex);
            fprintf("------------------------------------------------------------\n");

        end

        % ============================================================
        % Service / Control Channel 정보 출력
        % ============================================================
        function printChannels(ServiceChannels, ControlChannels)
        
            fprintf("\n");
            fprintf("[Channel Information]\n");
        
        
            %% ========================================================
            % Service Channels
            % =========================================================
            fprintf("  Service Channels\n");
        
            for channelIndex = 1:numel(ServiceChannels)
        
                packets = ServiceChannels(channelIndex).getPackets();
        
                % ------------------------------------------------------
                % Empty Channel
                % ------------------------------------------------------
                if isempty(packets)
        
                    fprintf("    Channel %2d : Empty\n", channelIndex);
        
                % ------------------------------------------------------
                % Packet 존재
                % ------------------------------------------------------
                else
        
                    fprintf("    Channel %2d\n", channelIndex);
        
                    for packetIndex = 1:numel(packets)
        
                        packet = packets(packetIndex);
        
                        switch packet.Type
        
                            % ==========================================
                            % DATA
                            % ==========================================
                            case PacketType.DATA
        
                                fprintf( ...
                                    "      DATA | Beam %d -> UT %d\n", ...
                                    packet.BeamId, ...
                                    packet.DestinationId ...
                                );
        
        
                            % ==========================================
                            % JAMMING
                            % ==========================================
                            case PacketType.JAMMING
        
                                fprintf( ...
                                    "      JAMMING | APJ %d -> Beam %d\n", ...
                                    packet.SourceId, ...
                                    packet.BeamId ...
                                );
        
        
                            % ==========================================
                            % 기타 Packet
                            % ==========================================
                            otherwise
        
                                fprintf( ...
                                    "      UNKNOWN PACKET\n" ...
                                );
        
                        end
        
                    end
        
                end
        
            end
        
        
        
            %% ========================================================
            % Control Channels
            % =========================================================
            fprintf("\n");
            fprintf("  Control Channels\n");
        
            for channelIndex = 1:numel(ControlChannels)
        
                packets = ControlChannels(channelIndex).getPackets();
        
                % ------------------------------------------------------
                % Empty Channel
                % ------------------------------------------------------
                if isempty(packets)
        
                    fprintf("    Channel %2d : Empty\n", channelIndex);
        
                % ------------------------------------------------------
                % Packet 존재
                % ------------------------------------------------------
                else
        
                    fprintf("    Channel %2d\n", channelIndex);
        
                    for packetIndex = 1:numel(packets)
        
                        packet = packets(packetIndex);
        
                        switch packet.Type
        
                            % ==========================================
                            % ACK
                            % ==========================================
                            case PacketType.ACK
        
                                fprintf( ...
                                    "      ACK  | UT %d -> Beam %d\n", ...
                                    packet.SourceId, ...
                                    packet.BeamId ...
                                );
        
        
                            % ==========================================
                            % NACK
                            % ==========================================
                            case PacketType.NACK
        
                                fprintf( ...
                                    "      NACK | UT %d -> Beam %d\n", ...
                                    packet.SourceId, ...
                                    packet.BeamId ...
                                );
        
        
                            % ==========================================
                            % 기타 Packet
                            % ==========================================
                            otherwise
        
                                fprintf( ...
                                    "      UNKNOWN PACKET\n" ...
                                );
        
                        end
        
                    end
        
                end
        
            end
        
        
            fprintf("\n");
        
        end

        % ============================================================
        % SINR 계산 디버그 출력
        % ============================================================
        function printSINRCalculation( ...
                utId, ...
                beamId, ...
                channelId, ...
                distance_m, ...
                desiredTxPower_dBm, ...
                desiredTxGain_dBi, ...
                desiredPower_W, ...
                interferencePackets, ...
                interferenceGain_dBi, ...
                interferencePowerEach_W, ...
                interferencePowerTotal_W, ...
                noisePower_W, ...
                SINR_dB, ...
                threshold_dB)
        
            fprintf("\n");
            fprintf("============================================================\n");
            fprintf("SINR Calculation - UT %d\n", utId);
            fprintf("============================================================\n");
        
            fprintf("  Desired Beam            : %d\n", beamId);
            fprintf("  Channel                 : %d\n", channelId);
            fprintf("  Satellite Distance      : %.2f km\n", distance_m / 1e3);
        
            fprintf("\n");
            fprintf("  [Desired Signal]\n");
            fprintf("    Tx Power              : %.2f dBm\n", desiredTxPower_dBm);
            fprintf("    Tx Gain               : %.2f dBi\n", desiredTxGain_dBi);
            fprintf("    Received Power        : %.6e W\n", desiredPower_W);
            fprintf("    Received Power        : %.2f dBm\n", ...
                10 * log10(desiredPower_W) + 30);
        
            fprintf("\n");
            fprintf("  [Interference]\n");
        
            if isempty(interferencePackets)
        
                fprintf("    None\n");
        
            else
        
                for i = 1:numel(interferencePackets)
        
                    fprintf( ...
                        "    Beam %2d | Tx Gain: %8.2f dBi | Rx Power: %.6e W (%.2f dBm)\n", ...
                        interferencePackets(i).BeamId, ...
                        interferenceGain_dBi(i), ...
                        interferencePowerEach_W(i), ...
                        10 * log10(interferencePowerEach_W(i)) + 30 ...
                    );
        
                end
            end
        
            fprintf("\n");
            fprintf("  [Power Summary]\n");
            fprintf("    Total Interference    : %.6e W (%.2f dBm)\n", ...
                interferencePowerTotal_W, ...
                10 * log10(max(interferencePowerTotal_W, realmin)) + 30);
        
            fprintf("    Noise Power           : %.6e W (%.2f dBm)\n", ...
                noisePower_W, ...
                10 * log10(noisePower_W) + 30);
        
            fprintf("\n");
            fprintf("  [Result]\n");
            fprintf("    SINR                   : %.2f dB\n", SINR_dB);
            fprintf("    Threshold              : %.2f dB\n", threshold_dB);
        
            if SINR_dB >= threshold_dB
                fprintf("    HARQ Result            : ACK\n");
            else
                fprintf("    HARQ Result            : NACK\n");
            end
        
            fprintf("============================================================\n");
        
        end


        % ============================================================
        % Interference-Free SNR Calibration Summary
        % ============================================================
        function printSNRCalibrationSummary(allSNR_dB)
        
            fprintf("\n");
            fprintf("============================================================\n");
            fprintf("Interference-Free SNR Calibration Summary\n");
            fprintf("============================================================\n");
        
            fprintf("  Number of Samples       : %d\n", numel(allSNR_dB));
            fprintf("  Minimum SNR             : %.2f dB\n", min(allSNR_dB));
            fprintf("  Maximum SNR             : %.2f dB\n", max(allSNR_dB));
            fprintf("  Mean SNR                : %.2f dB\n", mean(allSNR_dB));
            fprintf("  Median SNR              : %.2f dB\n", median(allSNR_dB));
        
            sortedSNR = sort(allSNR_dB);
        
            p1Index = max(1, ceil(0.01 * numel(sortedSNR)));
            p5Index = max(1, ceil(0.05 * numel(sortedSNR)));
        
            fprintf("  1%% Percentile           : %.2f dB\n", sortedSNR(p1Index));
            fprintf("  5%% Percentile           : %.2f dB\n", sortedSNR(p5Index));
        
            fprintf("============================================================\n");
        
        end


        % ============================================================
        % Simulation 결과 Summary
        % ============================================================
        function printSimulationSummary( ...
                numTimeSlots, ...
                numUTs, ...
                totalACKCount, ...
                totalTransmissionCount, ...
                slotSuccessRatios, ...
                targetACKResults, ...
                targetSINRResults_dB)
        
        
            %% ==================== 전체 결과 ====================
        
            totalNACKCount = ...
                totalTransmissionCount - totalACKCount;
        
            overallSuccessRatio = ...
                totalACKCount / totalTransmissionCount;
        
            overallFailureRatio = ...
                totalNACKCount / totalTransmissionCount;
        
        
            %% ==================== Target UT 결과 ====================
        
            targetACKCount = ...
                sum(targetACKResults);
        
            targetNACKCount = ...
                numTimeSlots - targetACKCount;
        
            targetSuccessRatio = ...
                targetACKCount / numTimeSlots;
        
        
            %% ==================== SINR 통계 ====================
        
            averageTargetSINR_dB = ...
                mean(targetSINRResults_dB);
        
            minimumTargetSINR_dB = ...
                min(targetSINRResults_dB);
        
            maximumTargetSINR_dB = ...
                max(targetSINRResults_dB);
        
        
            %% ==================== 출력 ====================
        
            fprintf("\n");
            fprintf("============================================================\n");
            fprintf("Simulation Summary\n");
            fprintf("============================================================\n");
        
            fprintf("  Number of Time Slots       : %d\n", numTimeSlots);
            fprintf("  Number of UTs              : %d\n", numUTs);
            fprintf("  Total Transmissions        : %d\n", totalTransmissionCount);
        
            fprintf("\n");
            fprintf("  [Overall HARQ]\n");
            fprintf("    ACK Count                : %d\n", totalACKCount);
            fprintf("    NACK Count               : %d\n", totalNACKCount);
            fprintf("    ACK Ratio                : %.2f %%\n", ...
                overallSuccessRatio * 100);
            fprintf("    NACK Ratio               : %.2f %%\n", ...
                overallFailureRatio * 100);
        
            fprintf("\n");
            fprintf("  [Slot Statistics]\n");
            fprintf("    Mean Success Ratio       : %.2f %%\n", ...
                mean(slotSuccessRatios) * 100);
            fprintf("    Minimum Success Ratio    : %.2f %%\n", ...
                min(slotSuccessRatios) * 100);
            fprintf("    Maximum Success Ratio    : %.2f %%\n", ...
                max(slotSuccessRatios) * 100);
        
            fprintf("\n");
            fprintf("  [Target UT]\n");
            fprintf("    ACK Count                : %d\n", targetACKCount);
            fprintf("    NACK Count               : %d\n", targetNACKCount);
            fprintf("    ACK Ratio                : %.2f %%\n", ...
                targetSuccessRatio * 100);
            fprintf("    Average SINR             : %.2f dB\n", ...
                averageTargetSINR_dB);
            fprintf("    Minimum SINR             : %.2f dB\n", ...
                minimumTargetSINR_dB);
            fprintf("    Maximum SINR             : %.2f dB\n", ...
                maximumTargetSINR_dB);
        
            fprintf("============================================================\n");
        
        end

        %% ========== Observation Sensing 결과 출력 ==========
        function printObservationSensing(owner, observationManager, ServiceChannels, Satellite)
        
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('RF Sensing - %s %d\n', char(string(owner.Type)), owner.Id);
            fprintf('============================================================\n');
        
            fprintf('  Number of Channels       : %d\n', observationManager.NumChannels);
        
            if owner.Type == NodeType.UT
                fprintf('  Associated Beam          : %d\n', owner.AssociatedBeamId);
            end
        
            fprintf('\n');
            fprintf('  [Per-Channel Sensing]\n');
        
        
            %% 채널별 상세 sensing 정보
            for channelIndex = 1:observationManager.NumChannels
        
                channel = ServiceChannels(channelIndex);
                packets = channel.getPackets();
        
                centerFrequency_Hz = channel.CenterFrequency_Hz;
        
                fprintf('\n');
                fprintf('    Channel %2d | %.3f MHz\n', ...
                    channelIndex, ...
                    centerFrequency_Hz / 1e6);
        
        
                numDataPackets = 0;
                numInterferingBeams = 0;
        
        
                %% 해당 채널의 DATA Beam 확인
                for packetIndex = 1:numel(packets)
        
                    packet = packets(packetIndex);
        
                    if packet.Type ~= PacketType.DATA
                        continue;
                    end
        
                    numDataPackets = numDataPackets + 1;
        
                    beam = Satellite.Beams(packet.BeamId);
        
        
                    %% Serving Beam 여부
                    isServingBeam = false;
        
                    if owner.Type == NodeType.UT
                        isServingBeam = ...
                            (beam.Id == owner.AssociatedBeamId);
                    end
        
        
                    %% Serving Beam이면 sensing에서 제외
                    if isServingBeam
        
                        fprintf( ...
                            '      Beam %2d -> UT %2d | Serving Beam | Excluded\n', ...
                            beam.Id, ...
                            packet.DestinationId ...
                        );
        
                        continue;
                    end
        
        
                    %% 실제 수신 전력 계산
                    receivedPower_W = ...
                        observationManager.calculateReceivedPower_W( ...
                            beam, ...
                            Satellite, ...
                            centerFrequency_Hz ...
                        );
        
                    receivedPower_dBm = ...
                        10 * log10(receivedPower_W) + 30;
        
                    numInterferingBeams = ...
                        numInterferingBeams + 1;
        
        
                    fprintf( ...
                        '      Beam %2d -> UT %2d | Rx Power: %8.2f dBm\n', ...
                        beam.Id, ...
                        packet.DestinationId, ...
                        receivedPower_dBm ...
                    );
        
                end
        
        
                %% Noise
                noisePower_W = ...
                    observationManager.calculateNoisePower_W( ...
                        channel.Bandwidth_Hz ...
                    );
        
                noisePower_dBm = ...
                    10 * log10(noisePower_W) + 30;
        
        
                %% Observation
                sensedPower_dBm = ...
                    observationManager.CurrentObservation(channelIndex);
        
        
                if numDataPackets == 0
        
                    fprintf('      DATA Beams           : None\n');
        
                elseif numInterferingBeams == 0
        
                    fprintf('      Interfering Beams    : None\n');
        
                end
        
        
                fprintf('      Noise Power          : %8.2f dBm\n', ...
                    noisePower_dBm);
        
                fprintf('      Sensed Power         : %8.2f dBm\n', ...
                    sensedPower_dBm);
        
            end
        
        
            %% Current Observation
            fprintf('\n');
            fprintf('  [Current Observation]\n');
        
            fprintf('    Channel :');
        
            for channelIndex = 1:observationManager.NumChannels
                fprintf(' %8d', channelIndex);
            end
        
            fprintf('\n');
        
            fprintf('    Power   :');
        
            for channelIndex = 1:observationManager.NumChannels
                fprintf(' %8.2f', ...
                    observationManager.CurrentObservation(channelIndex));
            end
        
            fprintf(' dBm\n');
        
            fprintf('============================================================\n');
        
        end
       

        %% ========== Control Channel 상세 출력 ==========
        function printChannelDetail(ControlChannels)
        
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('Control Channel Detail\n');
            fprintf('============================================================\n');
        
            for channelIndex = 1:numel(ControlChannels)
        
                packets = ControlChannels(channelIndex).getPackets();
        
                fprintf('\n');
                fprintf('  Channel %2d\n', channelIndex);
        
                if isempty(packets)
                    fprintf('    Empty\n');
                    continue;
                end
        
                for packetIndex = 1:numel(packets)
        
                    packet = packets(packetIndex);
        
                    % ACK / NACK 문자열
                    if packet.Type == PacketType.ACK
                        packetTypeStr = 'ACK';
                    elseif packet.Type == PacketType.NACK
                        packetTypeStr = 'NACK';
                    else
                        packetTypeStr = char(string(packet.Type));
                    end
        
                    % 기본 정보
                    fprintf('    %-4s | UT %2d -> Beam %2d\n', ...
                        packetTypeStr, ...
                        packet.SourceId, ...
                        packet.BeamId);
        
                    % Payload
                    if isempty(packet.Payload)
        
                        fprintf('           Payload : Empty\n');
        
                    else
        
                        fprintf('           Payload :');
        
                        for channelIndexPayload = 1:numel(packet.Payload)
                            fprintf(' %8.2f', packet.Payload(channelIndexPayload));
                        end
        
                        fprintf(' dBm\n');
        
                    end
        
                end
        
            end
        
            fprintf('\n');
            fprintf('============================================================\n');
        
        end


        %% ========== Beam StateManager 상태 출력 ==========
        function printBeamState(beam)
        
            stateManager = beam.StateManager;
        
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('Beam State - Beam %d\n', beam.Id);
            fprintf('============================================================\n');
        
            fprintf('  Associated UT            : %d\n', beam.AssociatedUTId);
            fprintf('  Selected Channel         : %d\n', beam.SelectedChannel);
            fprintf('  Number of Channels       : %d\n', stateManager.NumChannels);
            fprintf('  History Length           : %d\n', stateManager.HistoryLength);
            fprintf('  Number of Updates        : %d\n', stateManager.NumUpdates);
            fprintf('  Mode                     : %s\n', char(string(stateManager.Mode)));
        
            if stateManager.isReady()
                fprintf('  State Status             : READY\n');
            else
                fprintf('  State Status             : NOT READY (%d / %d)\n', ...
                    stateManager.NumUpdates, ...
                    stateManager.HistoryLength);
            end
        
        
            %% ============================================================
            %  Latest O / A / H
            % =============================================================
            fprintf('\n');
            fprintf('  [Latest O / A / H]\n');
        
            % Header
            fprintf('              ');
            for channelIndex = 1:stateManager.NumChannels
                fprintf(' %8s', sprintf('CH%d', channelIndex));
            end
            fprintf('\n');
        
        
            % Observation
            fprintf('    O       :');
            for channelIndex = 1:stateManager.NumChannels
                fprintf(' %8.2f', ...
                    stateManager.ObservationHistory(1, channelIndex));
            end
            fprintf('\n');
        
        
            % Action
            fprintf('    A       :');
            for channelIndex = 1:stateManager.NumChannels
                fprintf(' %8.0f', ...
                    stateManager.ActionHistory(1, channelIndex));
            end
            fprintf('\n');
        
        
            % HARQ
            fprintf('    H       :');
            for channelIndex = 1:stateManager.NumChannels
                fprintf(' %8.0f', ...
                    stateManager.HarqHistory(1, channelIndex));
            end
            fprintf('\n');
        
        
            %% ============================================================
            %  Observation History
            % =============================================================
            fprintf('\n');
            fprintf('  [Observation History]\n');
        
            DebugHelper.printStateHistoryMatrix( ...
                stateManager.ObservationHistory, ...
                stateManager.NumUpdates, ...
                stateManager.HistoryLength, ...
                stateManager.NumChannels, ...
                '%.2f' ...
            );
        
        
            %% ============================================================
            %  Action History
            % =============================================================
            fprintf('\n');
            fprintf('  [Action History]\n');
        
            DebugHelper.printStateHistoryMatrix( ...
                stateManager.ActionHistory, ...
                stateManager.NumUpdates, ...
                stateManager.HistoryLength, ...
                stateManager.NumChannels, ...
                '%.0f' ...
            );
        
        
            %% ============================================================
            %  HARQ History
            % =============================================================
            fprintf('\n');
            fprintf('  [HARQ History]\n');
        
            DebugHelper.printStateHistoryMatrix( ...
                stateManager.HarqHistory, ...
                stateManager.NumUpdates, ...
                stateManager.HistoryLength, ...
                stateManager.NumChannels, ...
                '%.0f' ...
            );
        
        
            %% ============================================================
            %  DQN State
            % =============================================================
            fprintf('\n');
            fprintf('  [DQN State]\n');
        
            state = stateManager.getState();
            stateSize = size(state);
        
            if numel(stateSize) == 2
                fprintf('    State Size             : %d x %d\n', ...
                    stateSize(1), ...
                    stateSize(2));
            else
                fprintf('    State Size             : %d x %d x %d\n', ...
                    stateSize(1), ...
                    stateSize(2), ...
                    stateSize(3));
            end
        
            fprintf('============================================================\n');
        
        end
        
        
        %% ========== State History Matrix 출력 ==========
        function printStateHistoryMatrix( ...
                history, ...
                numUpdates, ...
                historyLength, ...
                numChannels, ...
                numberFormat)
        
            % 왼쪽 시간축 폭
            timeWidth = 8;
        
            % 각 Channel 열 폭
            columnWidth = 10;
        
        
            %% Header
            fprintf('%*s', timeWidth, '');
        
            for channelIndex = 1:numChannels
                fprintf('%*s', ...
                    columnWidth, ...
                    sprintf('CH%d', channelIndex));
            end
        
            fprintf('\n');
        
        
            %% 실제 채워진 Row 수
            numFilledRows = min(numUpdates, historyLength);
        
        
            %% History 출력
            for historyIndex = 1:historyLength
        
                if historyIndex == 1
                    timeLabel = 't';
                else
                    timeLabel = sprintf('t-%d', historyIndex - 1);
                end
        
                fprintf('%*s', timeWidth, timeLabel);
        
        
                for channelIndex = 1:numChannels
        
                    value = history(historyIndex, channelIndex);
        
                    valueString = sprintf(numberFormat, value);
        
                    fprintf('%*s', ...
                        columnWidth, ...
                        valueString);
        
                end
        
                % 아직 데이터가 없는 Row 표시
                if historyIndex > numFilledRows
                    fprintf('   <- Empty');
                end
        
                fprintf('\n');
        
            end
        
        end


        %% ========== Beam Action Selection 출력 ==========
        function printBeamActionSelection(beam, selectionMethod, randomValue, qValues)
        
            agent = beam.Agent;
        
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('Beam Action Selection - Beam %d\n', beam.Id);
            fprintf('============================================================\n');
        
            fprintf('  Associated UT            : %d\n', beam.AssociatedUTId);
            fprintf('  Selection Method         : %s\n', selectionMethod);
            fprintf('  Random Value             : %.4f\n', randomValue);
            fprintf('  Epsilon                  : %.4f\n', agent.Epsilon);
            fprintf('  Selected Channel         : %d\n', beam.SelectedChannel);
        
        
            % ============================================================
            % Q-Values
            % ============================================================
            fprintf('\n');
            fprintf('  [Q-Values]\n');
        
            if isempty(qValues)
        
                fprintf('    Not Used (Random Action)\n');
        
            else
        
                qValues = qValues(:)';
        
                fprintf('    Channel :');
        
                for actionIndex = 1:agent.NumActions
                    fprintf(' %9d', actionIndex);
                end
        
                fprintf('\n');
        
        
                fprintf('    Q-Value :');
        
                for actionIndex = 1:agent.NumActions
                    fprintf(' %9.4f', qValues(actionIndex));
                end
        
                fprintf('\n');
        
            end
        
        
            % ============================================================
            % Pending Transition
            % ============================================================
            fprintf('\n');
            fprintf('  [Pending Transition]\n');
        
            if isempty(agent.PendingState)
                fprintf('    State S_t              : Empty\n');
            else
                stateSize = size(agent.PendingState);
        
                fprintf('    State S_t Size         : ');
        
                for dimensionIndex = 1:numel(stateSize)
        
                    if dimensionIndex > 1
                        fprintf(' x ');
                    end
        
                    fprintf('%d', stateSize(dimensionIndex));
        
                end
        
                fprintf('\n');
            end
        
            if isempty(agent.PendingAction)
                fprintf('    Action a_t             : Empty\n');
            else
                fprintf('    Action a_t             : %d\n', ...
                    agent.PendingAction);
            end
        
            if isempty(agent.PendingReward)
                fprintf('    Reward r_t             : Pending\n');
            else
                fprintf('    Reward r_t             : %.4f\n', ...
                    agent.PendingReward);
            end
        
        
            fprintf('============================================================\n');
        
        end


        %% ========== Beam Transition / Replay Buffer 출력 ==========
        function printBeamTransition(beam)
        
            agent = beam.Agent;
            buffer = agent.ReplayBuffer;
        
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('Beam Transition - Beam %d\n', beam.Id);
            fprintf('============================================================\n');
        
            fprintf('  Associated UT            : %d\n', beam.AssociatedUTId);
            fprintf('  Replay Buffer Count      : %d / %d\n', ...
                buffer.Count, ...
                buffer.Capacity);
        
            fprintf('  Next Buffer Position     : %d\n', ...
                buffer.Position);
        
        
            %% ============================================================
            %  마지막으로 저장된 Transition Index
            % =============================================================
            if buffer.Count == 0
                fprintf('\n');
                fprintf('  Replay Buffer is Empty\n');
                fprintf('============================================================\n');
                return;
            end
        
        
            % Position은 "다음에 저장할 위치"이므로,
            % 마지막 저장 위치는 Position - 1
            lastIndex = buffer.Position - 1;
        
            if lastIndex == 0
                lastIndex = buffer.Capacity;
            end
        
        
            %% ============================================================
            %  마지막 Transition 가져오기
            % =============================================================
            state = buffer.States{lastIndex};
            action = buffer.Actions(lastIndex);
            reward = buffer.Rewards(lastIndex);
            nextState = buffer.NextStates{lastIndex};
        
        
            fprintf('\n');
            fprintf('  [Last Stored Transition]\n');
        
            fprintf('    Buffer Index           : %d\n', lastIndex);
            fprintf('    Action a_t             : %d\n', action);
            fprintf('    Reward r_t             : %.2f\n', reward);
        
        
            %% State Size
            fprintf('    State S_t Size         : ');
            DebugHelper.printArraySize(state);
        
        
            %% Next State Size
            fprintf('    Next State S_t+1 Size  : ');
            DebugHelper.printArraySize(nextState);
        
        
            %% ============================================================
            %  State 최신 Row 확인
            % =============================================================
            fprintf('\n');
            fprintf('  [State S_t - Latest Observation Row]\n');
        
            DebugHelper.printStateFirstRow(state);
        
        
            fprintf('\n');
            fprintf('  [Next State S_t+1 - Latest Observation Row]\n');
        
            DebugHelper.printStateFirstRow(nextState);
        
        
            %% ============================================================
            %  State 변화 여부
            % =============================================================
            if isequal(state, nextState)
        
                fprintf('\n');
                fprintf('  [State Transition Check]\n');
                fprintf('    State Changed          : NO\n');
        
            else
        
                fprintf('\n');
                fprintf('  [State Transition Check]\n');
                fprintf('    State Changed          : YES\n');
        
            end
        
        
            %% ============================================================
            %  Pending Transition 초기화 여부
            % =============================================================
            fprintf('\n');
            fprintf('  [Pending Transition Status]\n');
        
            if isempty(agent.PendingState)
                fprintf('    Pending State          : Cleared\n');
            else
                fprintf('    Pending State          : Remains\n');
            end
        
            if isempty(agent.PendingAction)
                fprintf('    Pending Action         : Cleared\n');
            else
                fprintf('    Pending Action         : Remains\n');
            end
        
            if isempty(agent.PendingReward)
                fprintf('    Pending Reward         : Cleared\n');
            else
                fprintf('    Pending Reward         : Remains\n');
            end
        
        
            fprintf('============================================================\n');
        
        end
        
        
        %% ========== Array Size 출력 ==========
        function printArraySize(array)
        
            arraySize = size(array);
        
            for dimensionIndex = 1:numel(arraySize)
        
                if dimensionIndex > 1
                    fprintf(' x ');
                end
        
                fprintf('%d', arraySize(dimensionIndex));
        
            end
        
            fprintf('\n');
        
        end
        
        
        %% ========== State 첫 번째 Row 출력 ==========
        function printStateFirstRow(state)
        
            % O mode
            if ndims(state) == 2
        
                fprintf('    O :');
        
                for channelIndex = 1:size(state, 2)
                    fprintf(' %8.2f', state(1, channelIndex));
                end
        
                fprintf('\n');
        
        
            % OA / OAH mode
            else
        
                numStateChannels = size(state, 3);
        
        
                % Observation
                fprintf('    O :');
        
                for channelIndex = 1:size(state, 2)
                    fprintf(' %8.2f', state(1, channelIndex, 1));
                end
        
                fprintf('\n');
        
        
                % Action
                if numStateChannels >= 2
        
                    fprintf('    A :');
        
                    for channelIndex = 1:size(state, 2)
                        fprintf(' %8.0f', state(1, channelIndex, 2));
                    end
        
                    fprintf('\n');
        
                end
        
        
                % HARQ
                if numStateChannels >= 3
        
                    fprintf('    H :');
        
                    for channelIndex = 1:size(state, 2)
                        fprintf(' %8.0f', state(1, channelIndex, 3));
                    end
        
                    fprintf('\n');
        
                end
        
            end
        
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
        
        
            %% ============================================================
            % 현재 Beam State에 대한 Q-values
            %% ============================================================
        
            currentState = beam.StateManager.getState();
        
            % Beam1은 첫 번째 순차 선택자이므로 현재 occupancy = 0
            currentOccupancy = zeros(1, beam.Agent.NumActions);
        
            dlState = beam.Agent.convertStateToDLArray(currentState);
        
            dlOccupancy = ...
                beam.Agent.convertOccupancyToDLArray(currentOccupancy);
        
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

        %% ========== Beam별 HARQ Summary 출력 ==========
        function printPerBeamHARQSummary(beamACKCount, beamNACKCount)
        
            numBeams = numel(beamACKCount);
        
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('Per-Beam HARQ Summary\n');
            fprintf('============================================================\n');
        
            totalACK = sum(beamACKCount);
            totalNACK = sum(beamNACKCount);
            totalTransmissions = totalACK + totalNACK;
        
            fprintf('  Number of Beams          : %d\n', numBeams);
            fprintf('  Total Transmissions      : %d\n', totalTransmissions);
        
            fprintf('\n');
            fprintf('  [Per-Beam ACK Ratio]\n');
        
            for beamIndex = 1:numBeams
        
                ackCount = beamACKCount(beamIndex);
                nackCount = beamNACKCount(beamIndex);
        
                numTransmissions = ...
                    ackCount + nackCount;
        
                if numTransmissions > 0
                    ackRatio = ...
                        ackCount / numTransmissions;
                else
                    ackRatio = 0;
                end
        
                fprintf( ...
                    '    Beam %2d | ACK: %4d | NACK: %4d | ACK Ratio: %6.2f %%\n', ...
                    beamIndex, ...
                    ackCount, ...
                    nackCount, ...
                    ackRatio * 100 ...
                );
        
            end
        
        
            %% ============================================================
            % 평균 / 최저 / 최고 Beam
            % =============================================================
            ackRatios = zeros(1, numBeams);
        
            for beamIndex = 1:numBeams
        
                numTransmissions = ...
                    beamACKCount(beamIndex) + ...
                    beamNACKCount(beamIndex);
        
                if numTransmissions > 0
                    ackRatios(beamIndex) = ...
                        beamACKCount(beamIndex) / numTransmissions;
                end
        
            end
        
        
            [minimumRatio, minimumBeamId] = min(ackRatios);
            [maximumRatio, maximumBeamId] = max(ackRatios);
        
            fprintf('\n');
            fprintf('  [Beam Statistics]\n');
        
            fprintf('    Mean ACK Ratio         : %6.2f %%\n', ...
                mean(ackRatios) * 100);
        
            fprintf('    Minimum ACK Ratio      : %6.2f %% (Beam %d)\n', ...
                minimumRatio * 100, ...
                minimumBeamId);
        
            fprintf('    Maximum ACK Ratio      : %6.2f %% (Beam %d)\n', ...
                maximumRatio * 100, ...
                maximumBeamId);
        
            fprintf('============================================================\n');
        
        end

        % ========== Q-Value 출력 ==========
        function printQValues(agent, beamId)
        
            if isempty(agent.CurrentState)
                fprintf("Q-Value 출력 불가: CurrentState가 비어 있습니다.\n");
                return;
            end
        
            % 현재 State -> dlarray
            dlState = agent.convertStateToDLArray(agent.CurrentState);
        
            % Q-Network 추론
            dlQValues = predict(agent.QNetwork, dlState);
        
            % 일반 배열로 변환
            qValues = extractdata(dlQValues);
            qValues = qValues(:);
        
            % Greedy Action
            [maxQ, greedyAction] = max(qValues);
        
            % 두 번째로 큰 Q
            sortedQ = sort(qValues, 'descend');
        
            if numel(sortedQ) >= 2
                qGap = sortedQ(1) - sortedQ(2);
            else
                qGap = NaN;
            end
        
            fprintf("\n");
            fprintf("============================================================\n");
            fprintf("Q-Values - Beam %d\n", beamId);
            fprintf("============================================================\n");
        
            for action = 1:numel(qValues)
        
                if action == greedyAction
                    fprintf("  Channel %2d : %10.6f  <-- Greedy\n", ...
                        action, qValues(action));
                else
                    fprintf("  Channel %2d : %10.6f\n", ...
                        action, qValues(action));
                end
        
            end
        
            fprintf("\n");
            fprintf("  Greedy Action           : Channel %d\n", greedyAction);
            fprintf("  Maximum Q-Value         : %.6f\n", maxQ);
            fprintf("  Q Gap (1st - 2nd)       : %.6f\n", qGap);
            fprintf("============================================================\n");
        
        end

        % ============================================================
        % 매 슬롯 Beam의 Greedy Action / Q-gap 기록
        % ============================================================
        function recordBeamPolicy(slotIndex, qValues)
            persistent greedyLog gapLog slotLog
    
            if isempty(greedyLog)
                greedyLog = [];
                gapLog = [];
                slotLog = [];
            end
    
            if isempty(qValues)
                return;  % Random 선택이었던 슬롯은 기록 제외 (DQN 판단만 보고 싶으므로)
            end
    
            [sortedQ, idx] = sort(qValues(:), 'descend');
            greedyLog(end+1) = idx(1);
            gapLog(end+1) = sortedQ(1) - sortedQ(2);
            slotLog(end+1) = slotIndex;
    
            % 다음 호출을 위해 base workspace에도 저장 (printSummary에서 재사용)
            assignin('base', 'DebugGreedyLog', greedyLog);
            assignin('base', 'DebugGapLog', gapLog);
            assignin('base', 'DebugSlotLog', slotLog);
        end
    
        % ============================================================
        % 기록된 Greedy Action 이력 요약 출력
        % ============================================================
        function printBeamPolicySummary()
            greedyLog = evalin('base', 'DebugGreedyLog');
            gapLog = evalin('base', 'DebugGapLog');
    
            if isempty(greedyLog)
                fprintf('기록된 정책 데이터가 없습니다.\n');
                return;
            end
    
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('Beam Policy Trace Summary (DQN 판단만 집계, Random 제외)\n');
            fprintf('============================================================\n');
            fprintf('  총 기록 슬롯 수         : %d\n', numel(greedyLog));
    
            uniqueChannels = unique(greedyLog);
            fprintf('  선택된 서로 다른 채널 수 : %d\n', numel(uniqueChannels));
            fprintf('\n  [채널별 선택 빈도]\n');
            for ch = uniqueChannels
                cnt = sum(greedyLog == ch);
                fprintf('    Channel %2d : %4d회 (%.1f%%)\n', ch, cnt, 100*cnt/numel(greedyLog));
            end
    
            changes = sum(diff(greedyLog) ~= 0);
            fprintf('\n  연속 슬롯 간 Greedy Action이 바뀐 비율 : %d / %d (%.1f%%)\n', ...
                changes, numel(greedyLog)-1, 100*changes/(numel(greedyLog)-1));
            fprintf('  평균 Q-gap (1등-2등)                   : %.4f\n', mean(gapLog));
            fprintf('============================================================\n');
        end

        % ============================================================
        % 매 슬롯 전체 Beam의 채널 선택을 기록
        % ============================================================
        function recordAllBeamsPolicy(slotIndex, Satellite)
            persistent allChoices allSlots
            if isempty(allChoices)
                allChoices = {}; allSlots = [];
            end
    
            choices = zeros(1, numel(Satellite.Beams));
            for b = 1:numel(Satellite.Beams)
                choices(b) = Satellite.Beams(b).SelectedChannel;
            end
            allChoices{end+1} = choices;
            allSlots(end+1) = slotIndex;
    
            assignin('base', 'DebugAllChoices', allChoices);
            assignin('base', 'DebugAllSlots', allSlots);
        end
    
        % ============================================================
        % 충돌 패턴 요약: 슬롯별 충돌 빔 수, 그리고 시간에 따른 추세
        % ============================================================
        function printCollisionSummary(numChannels)
            allChoices = evalin('base', 'DebugAllChoices');
            allSlots = evalin('base', 'DebugAllSlots');
    
            if isempty(allChoices)
                fprintf('기록된 채널 선택 데이터가 없습니다.\n');
                return;
            end
    
            numSlots = numel(allChoices);
            collidedBeamCount = zeros(1, numSlots);  % 이 슬롯에 "충돌한(=같은 채널을 2개 이상이 쓴)" 빔 개수
    
            for s = 1:numSlots
                choices = allChoices{s};
                counts = histcounts(choices, 0.5:1:(numChannels+0.5));  % 채널별 사용 빔 수
                collidedBeamCount(s) = sum(counts(counts >= 2));  % 충돌에 연루된 빔 총합
            end
    
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('Beam Collision Pattern Summary\n');
            fprintf('============================================================\n');
            fprintf('  총 기록 슬롯 수                : %d\n', numSlots);
            fprintf('  전체 평균 충돌 빔 수/슬롯       : %.2f\n', mean(collidedBeamCount));
    
            % 전반부 vs 후반부 비교 (학습이 진행되며 충돌이 줄어드는지)
            half = floor(numSlots/2);
            firstHalfMean = mean(collidedBeamCount(1:half));
            secondHalfMean = mean(collidedBeamCount(half+1:end));
            fprintf('  전반부 평균 충돌 빔 수          : %.2f\n', firstHalfMean);
            fprintf('  후반부 평균 충돌 빔 수          : %.2f\n', secondHalfMean);
    
            if secondHalfMean < firstHalfMean * 0.8
                fprintf('  => 충돌이 시간에 따라 뚜렷이 감소 (수렴 신호)\n');
            elseif secondHalfMean > firstHalfMean * 1.2
                fprintf('  => 충돌이 오히려 증가 (추격전/발산 신호)\n');
            else
                fprintf('  => 충돌 수준이 거의 안 바뀜 (정체/추격전 신호)\n');
            end
    
            % 마지막 100슬롯만 따로 (수렴했다면 여기서 낮아야 정상)
            last100 = collidedBeamCount(max(1,numSlots-99):end);
            fprintf('  마지막 100슬롯 평균 충돌 빔 수  : %.2f\n', mean(last100));
            fprintf('============================================================\n');
        end

        %% ========== APJ SINR 추정 과정 출력 ==========
        function printAPJSINREstimation( ...
                APJ, ...
                targetPacket, ...
                centerFrequency_Hz, ...
                bandwidth_Hz, ...
                distance, ...
                desiredTxPower_dBm, ...
                desiredTxGain_dBi, ...
                desiredPower_W, ...
                interferencePackets, ...
                interferenceGain_dBi, ...
                interferencePowerEach_W, ...
                interferencePower_W, ...
                noisePower_W, ...
                SINR_dB)
        
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('APJ SINR Estimation - APJ %d\n', APJ.Id);
            fprintf('============================================================\n');
        
            %% 기본 정보
            fprintf('  Target UT ID             : %d\n', APJ.TargetUTId);
            fprintf('  Observed Channel         : %d\n', targetPacket.ChannelId);
            fprintf('  Target Beam ID           : %d\n', targetPacket.BeamId);
        
            fprintf('  Center Frequency         : %.3f MHz\n', ...
                centerFrequency_Hz / 1e6);
        
            fprintf('  Channel Bandwidth        : %.3f kHz\n', ...
                bandwidth_Hz / 1e3);
        
            fprintf('\n');
        
            %% APJ 위치
            fprintf('  [APJ Geometry]\n');
        
            fprintf('    Position               : (%.2f, %.2f, %.2f) km\n', ...
                APJ.Position(1) / 1e3, ...
                APJ.Position(2) / 1e3, ...
                APJ.Position(3) / 1e3);
        
            fprintf('    Satellite Distance     : %.3f km\n', ...
                distance / 1e3);
        
            fprintf('\n');
        
            %% Desired Signal
            fprintf('  [Desired Signal]\n');
        
            fprintf('    Beam ID                : %d\n', ...
                targetPacket.BeamId);
        
            fprintf('    Tx Power               : %.3f dBm\n', ...
                desiredTxPower_dBm);
        
            fprintf('    Tx Gain @ APJ          : %.3f dBi\n', ...
                desiredTxGain_dBi);
        
            fprintf('    APJ Rx Gain            : %.3f dBi\n', ...
                APJ.RxGain_dBi);
        
            fprintf('    Received Power         : %.3e W\n', ...
                desiredPower_W);
        
            fprintf('                           : %.3f dBm\n', ...
                DebugHelper.wattToDbm(desiredPower_W));
        
            fprintf('\n');
        
            %% Interference
            fprintf('  [Interference]\n');
        
            numInterference = numel(interferencePackets);
        
            fprintf('    Number of Interferers  : %d\n', ...
                numInterference);
        
            if numInterference == 0
        
                fprintf('    No co-channel interfering beam\n');
        
            else
        
                for interferenceIndex = 1:numInterference
        
                    packet = interferencePackets(interferenceIndex);
        
                    fprintf('\n');
                    fprintf('    Interferer %d\n', interferenceIndex);
        
                    fprintf('      Beam ID              : %d\n', ...
                        packet.BeamId);
        
                    fprintf('      Channel              : %d\n', ...
                        packet.ChannelId);
        
                    fprintf('      Tx Gain @ APJ        : %.3f dBi\n', ...
                        interferenceGain_dBi(interferenceIndex));
        
                    fprintf('      Received Power       : %.3e W\n', ...
                        interferencePowerEach_W(interferenceIndex));
        
                    fprintf('                           : %.3f dBm\n', ...
                        DebugHelper.wattToDbm( ...
                            interferencePowerEach_W(interferenceIndex)));
        
                end
            end
        
            fprintf('\n');
        
            fprintf('    Total Interference     : %.3e W\n', ...
                interferencePower_W);
        
            if interferencePower_W > 0
                fprintf('                           : %.3f dBm\n', ...
                    DebugHelper.wattToDbm(interferencePower_W));
            else
                fprintf('                           : -Inf dBm\n');
            end
        
            fprintf('\n');
        
            %% Noise
            fprintf('  [Noise]\n');
        
            fprintf('    Noise Temperature      : %.2f K\n', ...
                APJ.NoiseTemperature);
        
            fprintf('    Noise Figure           : %.2f dB\n', ...
                APJ.NoiseFigure_dB);
        
            fprintf('    Noise Power            : %.3e W\n', ...
                noisePower_W);
        
            fprintf('                           : %.3f dBm\n', ...
                DebugHelper.wattToDbm(noisePower_W));
        
            fprintf('\n');
        
            %% 최종 SINR
            fprintf('  [Estimated SINR]\n');
        
            fprintf('    Desired Power          : %.3f dBm\n', ...
                DebugHelper.wattToDbm(desiredPower_W));
        
            if interferencePower_W > 0
                fprintf('    Interference Power     : %.3f dBm\n', ...
                    DebugHelper.wattToDbm(interferencePower_W));
            else
                fprintf('    Interference Power     : -Inf dBm\n');
            end
        
            fprintf('    Noise Power            : %.3f dBm\n', ...
                DebugHelper.wattToDbm(noisePower_W));
        
            fprintf('    Estimated SINR         : %.3f dB\n', ...
                SINR_dB);
        
            fprintf('    SINR Threshold         : %.3f dB\n', ...
                APJ.SINRThreshold_dB);
        
            if SINR_dB >= APJ.SINRThreshold_dB
                fprintf('    Pseudo HARQ            : ACK\n');
            else
                fprintf('    Pseudo HARQ            : NACK\n');
            end
        
            fprintf('============================================================\n');
        
        end

        %% ========== Watt -> dBm ==========

        function power_dBm = wattToDbm(power_W)
        
            if power_W <= 0
        
                power_dBm = -Inf;
        
                return;
        
            end
        
            power_dBm = 10 * log10(power_W) + 30;
        
        end


        %% ========== APJ Pseudo HARQ Evaluation ==========
        function printAPJPseudoHARQEvaluation( ...
                actualACKHistory, ...
                pseudoACKHistory, ...
                actualSINRHistory_dB, ...
                estimatedSINRHistory_dB)
        
            %% 1. 유효한 HARQ Sample만 추출
            validHARQ = ...
                ~isnan(actualACKHistory) & ...
                ~isnan(pseudoACKHistory);
        
            actualACK = logical(actualACKHistory(validHARQ));
            pseudoACK = logical(pseudoACKHistory(validHARQ));
        
            numHARQSamples = numel(actualACK);
        
            if numHARQSamples == 0
                fprintf('\n');
                fprintf('============================================================\n');
                fprintf('APJ Pseudo HARQ Evaluation\n');
                fprintf('============================================================\n');
                fprintf('  No valid HARQ samples available.\n');
                fprintf('============================================================\n');
                return;
            end
        
        
            %% 2. Confusion Matrix
            % Positive = ACK
            % Negative = NACK
        
            TP = sum(actualACK == true  & pseudoACK == true);
            TN = sum(actualACK == false & pseudoACK == false);
            FP = sum(actualACK == false & pseudoACK == true);
            FN = sum(actualACK == true  & pseudoACK == false);
        
        
            %% 3. HARQ Evaluation Metrics
            accuracy = (TP + TN) / numHARQSamples;
        
            if (TP + FP) > 0
                precision = TP / (TP + FP);
            else
                precision = NaN;
            end
        
            if (TP + FN) > 0
                recall = TP / (TP + FN);
            else
                recall = NaN;
            end
        
            if ~isnan(precision) && ~isnan(recall) && ...
                    (precision + recall) > 0
        
                f1Score = ...
                    2 * precision * recall / ...
                    (precision + recall);
        
            else
                f1Score = NaN;
            end
        
        
            %% 4. 실제 / Pseudo ACK Ratio
            actualACKRatio = mean(actualACK);
            pseudoACKRatio = mean(pseudoACK);
        
        
            %% 5. SINR 유효 Sample 추출
            validSINR = ...
                ~isnan(actualSINRHistory_dB) & ...
                ~isnan(estimatedSINRHistory_dB);
        
            actualSINR = ...
                actualSINRHistory_dB(validSINR);
        
            estimatedSINR = ...
                estimatedSINRHistory_dB(validSINR);
        
            numSINRSamples = numel(actualSINR);
        
        
            %% 6. SINR Error 계산
            if numSINRSamples > 0
        
                % estimated - actual
                sinrError_dB = ...
                    estimatedSINR - actualSINR;
        
                meanError_dB = ...
                    mean(sinrError_dB);
        
                mae_dB = ...
                    mean(abs(sinrError_dB));
        
                rmse_dB = ...
                    sqrt(mean(sinrError_dB .^ 2));
        
                maxAbsoluteError_dB = ...
                    max(abs(sinrError_dB));
        
                meanActualSINR_dB = ...
                    mean(actualSINR);
        
                meanEstimatedSINR_dB = ...
                    mean(estimatedSINR);
        
            else
        
                meanError_dB = NaN;
                mae_dB = NaN;
                rmse_dB = NaN;
                maxAbsoluteError_dB = NaN;
        
                meanActualSINR_dB = NaN;
                meanEstimatedSINR_dB = NaN;
        
            end
        
        
            %% 7. 출력
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('APJ Pseudo HARQ Evaluation\n');
            fprintf('============================================================\n');
        
            fprintf('  Number of HARQ Samples   : %d\n', ...
                numHARQSamples);
        
            fprintf('  Number of SINR Samples   : %d\n', ...
                numSINRSamples);
        
        
            %% HARQ Ground Truth
            fprintf('\n');
            fprintf('  [HARQ Distribution]\n');
        
            fprintf('    Actual ACK Ratio       : %6.2f %%\n', ...
                actualACKRatio * 100);
        
            fprintf('    Pseudo ACK Ratio       : %6.2f %%\n', ...
                pseudoACKRatio * 100);
        
        
            %% Confusion Matrix
            fprintf('\n');
            fprintf('  [HARQ Confusion Matrix]\n');
            fprintf('    Positive Class         : ACK\n');
        
            fprintf('    TP (ACK  -> ACK)       : %d\n', TP);
            fprintf('    TN (NACK -> NACK)      : %d\n', TN);
            fprintf('    FP (NACK -> ACK)       : %d\n', FP);
            fprintf('    FN (ACK  -> NACK)      : %d\n', FN);
        
        
            %% Prediction Performance
            fprintf('\n');
            fprintf('  [HARQ Prediction Performance]\n');
        
            fprintf('    Accuracy               : %6.2f %%\n', ...
                accuracy * 100);
        
            fprintf('    Precision              : %6.2f %%\n', ...
                precision * 100);
        
            fprintf('    Recall                 : %6.2f %%\n', ...
                recall * 100);
        
            fprintf('    F1 Score               : %6.2f %%\n', ...
                f1Score * 100);
        
        
            %% SINR
            fprintf('\n');
            fprintf('  [SINR Estimation]\n');
        
            fprintf('    Mean Actual SINR       : %8.3f dB\n', ...
                meanActualSINR_dB);
        
            fprintf('    Mean Estimated SINR    : %8.3f dB\n', ...
                meanEstimatedSINR_dB);
        
        
            fprintf('\n');
            fprintf('  [SINR Estimation Error]\n');
        
            fprintf('    Mean Error             : %+8.3f dB\n', ...
                meanError_dB);
        
            fprintf('    MAE                    : %8.3f dB\n', ...
                mae_dB);
        
            fprintf('    RMSE                   : %8.3f dB\n', ...
                rmse_dB);
        
            fprintf('    Maximum Absolute Error : %8.3f dB\n', ...
                maxAbsoluteError_dB);
        
            fprintf('============================================================\n');
        
        end

        function printAPJPredictionQValues(slotIndex, predictedChannel, qValues)

            fprintf("\n");
            fprintf("============================================================\n");
            fprintf("APJ Next-Channel Prediction\n");
            fprintf("============================================================\n");
        
            fprintf("  Current Slot             : %d\n", slotIndex);
            fprintf("  Prediction For           : Slot %d\n", slotIndex + 1);
            fprintf("  Predicted Channel        : %d\n", predictedChannel);
        
            fprintf("\n");
            fprintf("  [Q-Values]\n");
        
            if isempty(qValues)
                fprintf("    Q-values unavailable (epsilon random action)\n");
            else
        
                for channelIndex = 1:numel(qValues)
        
                    fprintf( ...
                        "    CH %2d : %10.6f", ...
                        channelIndex, ...
                        qValues(channelIndex) ...
                    );
        
                    if channelIndex == predictedChannel
                        fprintf("   <-- Selected");
                    end
        
                    fprintf("\n");
        
                end
        
                sortedQ = sort(qValues, "descend");
        
                if numel(sortedQ) >= 2
                    qMargin = sortedQ(1) - sortedQ(2);
        
                    fprintf("\n");
                    fprintf("    Top-1 / Top-2 Margin   : %.6f\n", ...
                        qMargin);
                end
        
            end
        
            fprintf("============================================================\n");
        
        end

        function printAPJTraining(APJ, slotIndex, observedChannel, ...
            estimatedSINR_dB, pseudoHARQ, lossValue, trainingInfo, qValues)
        
            fprintf("\n");
            fprintf("============================================================\n");
            fprintf("APJ Agent Training\n");
            fprintf("============================================================\n");
        
            fprintf("  Slot                     : %d\n", slotIndex);
        
            fprintf("\n");
            fprintf("  [Observation]\n");
            fprintf("    Observed Channel       : %d\n", observedChannel);
            fprintf("    Estimated SINR         : %.3f dB\n", estimatedSINR_dB);
        
            if pseudoHARQ == PacketType.ACK
                fprintf("    Pseudo HARQ            : ACK\n");
            else
                fprintf("    Pseudo HARQ            : NACK\n");
            end
        
            fprintf("\n");
            fprintf("  [Training]\n");
            fprintf("    Replay Buffer Count    : %d\n", ...
                APJ.Agent.ReplayBuffer.Count);
            fprintf("    Batch Size             : %d\n", ...
                APJ.Agent.BatchSize);
            fprintf("    Training Step          : %d\n", ...
                APJ.Agent.TrainingStep);
            fprintf("    Epsilon                : %.6f\n", ...
                APJ.Agent.Epsilon);
        
            if isempty(lossValue)
                fprintf("    Status                 : WAITING\n");
                fprintf("    Loss                   : N/A\n");
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
        
            fprintf("\n");
            fprintf("  [Next Channel Prediction]\n");
            fprintf("    Predicted Channel      : %d\n", ...
                APJ.PredictedChannel);
        
            if ~isempty(qValues)
                fprintf("\n");
                fprintf("    Q-Values\n");
        
                for channelIndex = 1:numel(qValues)
                    fprintf("      CH %2d : %10.6f", ...
                        channelIndex, qValues(channelIndex));
        
                    if channelIndex == APJ.PredictedChannel
                        fprintf("  <-- Predicted");
                    end
        
                    fprintf("\n");
                end
            end
        
            fprintf("============================================================\n");
        end

        %% ============================================================
        % APJ Prediction 기록
        % ============================================================
        function recordAPJPrediction(slotIndex, predictedChannel, actualChannel)

            newData.slot = slotIndex;
            newData.predicted = predictedChannel;
            newData.actual = actualChannel;

            data = DebugHelper.APJPredictionStorage('add', newData);

            totalCount = numel(data.actual);

            isCorrect = ...
                (predictedChannel == actualChannel);

            cumulativeAccuracy = ...
                mean(data.predicted == data.actual);

            recentWindow = min(100, totalCount);

            recentPredicted = ...
                data.predicted(end-recentWindow+1:end);

            recentActual = ...
                data.actual(end-recentWindow+1:end);

            recentAccuracy = ...
                mean(recentPredicted == recentActual);


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

            fprintf('  Cumulative Accuracy      : %.2f %%\n', ...
                cumulativeAccuracy * 100);

            fprintf('  Recent Accuracy (%d)     : %.2f %%\n', ...
                recentWindow, recentAccuracy * 100);

            fprintf('============================================================\n');

        end

            %% ============================================================
        % APJ Prediction Storage
        % ============================================================
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
                %% ============================================================
        % APJ Channel Prediction 최종 Summary
        % ============================================================
        function printAPJPredictionSummary(numChannels)

            data = DebugHelper.APJPredictionStorage('get', []);

            predicted = data.predicted;
            actual = data.actual;
            slots = data.slots;

            totalCount = numel(actual);

            fprintf('\n');
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('APJ CHANNEL PREDICTION SUMMARY\n');
            fprintf('============================================================\n');

            if totalCount == 0
                fprintf('  No prediction samples recorded.\n');
                fprintf('============================================================\n');
                return;
            end


            %% --------------------------------------------------------
            % Overall Performance
            % ---------------------------------------------------------
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

            fprintf('    Accuracy               : %6.2f %%\n', ...
                accuracy * 100);

            fprintf('    Random Baseline        : %6.2f %%\n', ...
                randomBaseline * 100);

            fprintf('    Improvement over Random: %6.2f x\n', ...
                accuracy / randomBaseline);


            %% --------------------------------------------------------
            % Recent Performance
            % ---------------------------------------------------------
            recentWindow = min(100, totalCount);

            recentPredicted = ...
                predicted(end-recentWindow+1:end);

            recentActual = ...
                actual(end-recentWindow+1:end);

            recentAccuracy = ...
                mean(recentPredicted == recentActual);

            fprintf('\n');
            fprintf('  [Recent Performance]\n');

            fprintf('    Window Size            : %d\n', ...
                recentWindow);

            fprintf('    Accuracy               : %6.2f %%\n', ...
                recentAccuracy * 100);


            %% --------------------------------------------------------
            % Per-Channel Performance
            % ---------------------------------------------------------
            fprintf('\n');
            fprintf('  [Per-Channel Prediction Performance]\n');

            for ch = 1:numChannels

                actualMask = (actual == ch);

                actualCount = sum(actualMask);

                predictedCount = ...
                    sum(predicted == ch);

                correctChannelCount = ...
                    sum((predicted == ch) & (actual == ch));

                if actualCount > 0
                    channelRecall = ...
                        correctChannelCount / actualCount;
                else
                    channelRecall = NaN;
                end

                if isnan(channelRecall)

                    fprintf(['    CH %2d | Actual: %4d | Predicted: %4d | ' ...
                        'Correct: %4d | Recall:   N/A\n'], ...
                        ch, ...
                        actualCount, ...
                        predictedCount, ...
                        correctChannelCount);

                else

                    fprintf(['    CH %2d | Actual: %4d | Predicted: %4d | ' ...
                        'Correct: %4d | Recall: %6.2f %%\n'], ...
                        ch, ...
                        actualCount, ...
                        predictedCount, ...
                        correctChannelCount, ...
                        channelRecall * 100);

                end

            end


            %% --------------------------------------------------------
            % Confusion Matrix
            % Row    = Actual
            % Column = Predicted
            % ---------------------------------------------------------
            confusionMatrix = zeros(numChannels, numChannels);

            for i = 1:totalCount

                actualCh = actual(i);
                predictedCh = predicted(i);

                confusionMatrix(actualCh, predictedCh) = ...
                    confusionMatrix(actualCh, predictedCh) + 1;

            end


            fprintf('\n');
            fprintf('  [Channel Confusion Matrix]\n');
            fprintf('    Row = Actual, Column = Predicted\n\n');

            fprintf('          ');

            for ch = 1:numChannels
                fprintf('P%-5d', ch);
            end

            fprintf('\n');

            for actualCh = 1:numChannels

                fprintf('    A%-3d  ', actualCh);

                for predictedCh = 1:numChannels

                    fprintf('%-6d', ...
                        confusionMatrix(actualCh, predictedCh));

                end

                fprintf('\n');

            end


            %% --------------------------------------------------------
            % Best / Worst Channel Recall
            % ---------------------------------------------------------
            channelRecalls = nan(1, numChannels);

            for ch = 1:numChannels

                actualCount = sum(actual == ch);

                if actualCount > 0

                    correctChannelCount = ...
                        sum((actual == ch) & ...
                            (predicted == ch));

                    channelRecalls(ch) = ...
                        correctChannelCount / actualCount;

                end

            end

            validChannels = find(~isnan(channelRecalls));

            if ~isempty(validChannels)

                [bestRecall, bestIdx] = ...
                    max(channelRecalls(validChannels));

                [worstRecall, worstIdx] = ...
                    min(channelRecalls(validChannels));

                bestChannel = ...
                    validChannels(bestIdx);

                worstChannel = ...
                    validChannels(worstIdx);

                fprintf('\n');
                fprintf('  [Channel Statistics]\n');

                fprintf('    Best Predicted Channel : CH %d (%.2f %%)\n', ...
                    bestChannel, ...
                    bestRecall * 100);

                fprintf('    Worst Predicted Channel: CH %d (%.2f %%)\n', ...
                    worstChannel, ...
                    worstRecall * 100);

            end


            fprintf('============================================================\n');

        end

        function recordBeamSelfPrediction( ...
            slotIndex, ...
            predictedChannel, ...
            actualChannel)
    
        persistent slots
        persistent predictedHistory
        persistent actualHistory
    
        if isempty(slots)
            slots = [];
            predictedHistory = [];
            actualHistory = [];
        end
    
    
        slots(end + 1) = ...
            slotIndex;
    
        predictedHistory(end + 1) = ...
            predictedChannel;
    
        actualHistory(end + 1) = ...
            actualChannel;
    
    
        %% ============================================================
        % Accuracy
        %% ============================================================
    
        correctHistory = ...
            (predictedHistory == actualHistory);
    
        totalCount = ...
            numel(correctHistory);
    
        correctCount = ...
            sum(correctHistory);
    
        cumulativeAccuracy = ...
            mean(correctHistory);
    
    
        %% ============================================================
        % Recent 100
        %% ============================================================
    
        recentWindow = ...
            min(100, totalCount);
    
        recentAccuracy = ...
            mean( ...
                correctHistory( ...
                    end-recentWindow+1:end ...
                ) ...
            );
    
    
        %% ============================================================
        % Current Result
        %% ============================================================
    
        isCorrect = ...
            (predictedChannel == actualChannel);
    
    
        fprintf('\n');
        fprintf('============================================================\n');
        fprintf('Beam1 Self Next-Channel Prediction Evaluation\n');
        fprintf('============================================================\n');
    
        fprintf('  Slot                     : %d\n', ...
            slotIndex);
    
        fprintf('  Predicted Channel        : %d\n', ...
            predictedChannel);
    
        fprintf('  Actual Selected Channel  : %d\n', ...
            actualChannel);
    
    
        if isCorrect
    
            fprintf('  Result                   : HIT\n');
    
        else
    
            fprintf('  Result                   : MISS\n');
    
        end
    
    
        fprintf('\n');
        fprintf('  [Prediction Performance]\n');
    
        fprintf('    Total Predictions      : %d\n', ...
            totalCount);
    
        fprintf('    Correct Predictions    : %d\n', ...
            correctCount);
    
        fprintf('    Cumulative Accuracy    : %.2f %%\n', ...
            cumulativeAccuracy * 100);
    
        fprintf('    Recent Accuracy (%3d) : %.2f %%\n', ...
            recentWindow, ...
            recentAccuracy * 100);
    
        fprintf('============================================================\n');
    
        end

        function printBeamSelfPredictionQValues( ...
            slotIndex, ...
            predictedChannel, ...
            qValues)
    
        fprintf('\n');
        fprintf('============================================================\n');
        fprintf('Beam1 Self Next-Channel Prediction\n');
        fprintf('============================================================\n');
    
        fprintf('  Current Slot             : %d\n', ...
            slotIndex);
    
        fprintf('  Prediction Target        : Slot %d\n', ...
            slotIndex + 1);
    
        fprintf('  Predicted Channel        : %d\n', ...
            predictedChannel);
    
    
        fprintf('\n');
        fprintf('  [Q-Values]\n');
    
    
        for channelIndex = 1:numel(qValues)
    
            fprintf('    CH %2d : %10.6f', ...
                channelIndex, ...
                qValues(channelIndex));
    
    
            if channelIndex == predictedChannel
    
                fprintf('  <-- Predicted');
    
            end
    
    
            fprintf('\n');
    
        end
    
    
        fprintf('============================================================\n');
    
        end

        function compareOracleTransitions( ...
            slotIndex, ...
            beamState, ...
            beamAction, ...
            beamReward, ...
            beamNextState, ...
            apjState, ...
            apjAction, ...
            apjReward, ...
            apjNextState)
    
        %% ============================================================
        % State 차이
        %% ============================================================
    
        stateDifference = ...
            double(beamState(:)) - double(apjState(:));
    
        stateMAE = ...
            mean(abs(stateDifference));
    
        stateRMSE = ...
            sqrt(mean(stateDifference.^2));
    
        stateMaxError = ...
            max(abs(stateDifference));
    
        stateExactlyEqual = ...
            isequaln(beamState, apjState);
    
    
        %% ============================================================
        % Action
        %% ============================================================
    
        actionEqual = ...
            isequal(beamAction, apjAction);
    
    
        %% ============================================================
        % Reward
        %% ============================================================
    
        rewardEqual = ...
            isequal(beamReward, apjReward);
    
    
        %% ============================================================
        % Next State
        %% ============================================================
    
        nextStateDifference = ...
            double(beamNextState(:)) - double(apjNextState(:));
    
        nextStateMAE = ...
            mean(abs(nextStateDifference));
    
        nextStateRMSE = ...
            sqrt(mean(nextStateDifference.^2));
    
        nextStateMaxError = ...
            max(abs(nextStateDifference));
    
        nextStateExactlyEqual = ...
            isequaln(beamNextState, apjNextState);
    
    
        %% ============================================================
        % Transition 전체 일치 여부
        %% ============================================================
    
        transitionEqual = ...
            stateExactlyEqual && ...
            actionEqual && ...
            rewardEqual && ...
            nextStateExactlyEqual;
    
    
        %% ============================================================
        % 출력
        %% ============================================================
    
        fprintf('\n');
        fprintf('============================================================\n');
        fprintf('FULL ORACLE TRANSITION COMPARISON\n');
        fprintf('============================================================\n');
    
        fprintf('  Slot                     : %d\n', slotIndex);
    
    
        fprintf('\n');
        fprintf('  [S_t Comparison]\n');
    
        fprintf('    Exact Match            : %s\n', ...
            DebugHelper.boolToString(stateExactlyEqual));
    
        fprintf('    MAE                    : %.10f\n', ...
            stateMAE);
    
        fprintf('    RMSE                   : %.10f\n', ...
            stateRMSE);
    
        fprintf('    Maximum Error          : %.10f\n', ...
            stateMaxError);
    
    
        fprintf('\n');
        fprintf('  [A_t Comparison]\n');
    
        fprintf('    Beam1 Action           : %d\n', ...
            beamAction);
    
        fprintf('    APJ Action             : %d\n', ...
            apjAction);
    
        fprintf('    Match                  : %s\n', ...
            DebugHelper.boolToString(actionEqual));
    
    
        fprintf('\n');
        fprintf('  [R_t Comparison]\n');
    
        fprintf('    Beam1 Reward           : %d\n', ...
            beamReward);
    
        fprintf('    APJ Reward             : %d\n', ...
            apjReward);
    
        fprintf('    Match                  : %s\n', ...
            DebugHelper.boolToString(rewardEqual));
    
    
        fprintf('\n');
        fprintf('  [S_t+1 Comparison]\n');
    
        fprintf('    Exact Match            : %s\n', ...
            DebugHelper.boolToString(nextStateExactlyEqual));
    
        fprintf('    MAE                    : %.10f\n', ...
            nextStateMAE);
    
        fprintf('    RMSE                   : %.10f\n', ...
            nextStateRMSE);
    
        fprintf('    Maximum Error          : %.10f\n', ...
            nextStateMaxError);
    
    
        fprintf('\n');
        fprintf('  [Transition Result]\n');
    
        fprintf('    Full Transition Match  : %s\n', ...
            DebugHelper.boolToString(transitionEqual));
    
        fprintf('============================================================\n');
    
        end


        function compareBeamAPJQValues( ...
            slotIndex, ...
            comparisonStage, ...
            beamQ, ...
            apjQ)
    
        %% ============================================================
        % Vector 정리
        %% ============================================================
    
        beamQ = double(beamQ(:));
        apjQ  = double(apjQ(:));
    
        numActions = numel(beamQ);
    
    
        %% ============================================================
        % Q Error
        %% ============================================================
    
        qDifference = beamQ - apjQ;
    
        qMAE = mean(abs(qDifference));
    
        qRMSE = sqrt(mean(qDifference.^2));
    
        qMaxError = max(abs(qDifference));
    
    
        %% ============================================================
        % Cosine Similarity
        %% ============================================================
    
        denominator = norm(beamQ) * norm(apjQ);
    
        if denominator > 0
            cosineSimilarity = dot(beamQ, apjQ) / denominator;
        else
            cosineSimilarity = NaN;
        end
    
    
        %% ============================================================
        % Pearson Correlation
        %% ============================================================
    
        if std(beamQ) > 0 && std(apjQ) > 0
    
            correlationMatrix = corrcoef(beamQ, apjQ);
    
            qCorrelation = correlationMatrix(1, 2);
    
        else
            qCorrelation = NaN;
        end
    
    
        %% ============================================================
        % Greedy Channel
        %% ============================================================
    
        [beamBestQ, beamGreedy] = max(beamQ);
    
        [apjBestQ, apjGreedy] = max(apjQ);
    
        greedyMatch = ...
            (beamGreedy == apjGreedy);
    
    
        %% ============================================================
        % Beam Top-2 Margin
        %% ============================================================
    
        beamSortedQ = sort(beamQ, 'descend');
    
        if numActions >= 2
            beamQMargin = ...
                beamSortedQ(1) - beamSortedQ(2);
        else
            beamQMargin = NaN;
        end
    
    
        %% ============================================================
        % APJ Top-2 Margin
        %% ============================================================
    
        apjSortedQ = sort(apjQ, 'descend');
    
        if numActions >= 2
            apjQMargin = ...
                apjSortedQ(1) - apjSortedQ(2);
        else
            apjQMargin = NaN;
        end
    
    
        %% ============================================================
        % ★ POST APJ TRAIN 결과만 누적 기록
        %
        % 실제 APJ prediction에 사용되는 network가
        % train() 이후 network이므로 POST 기준으로 분석
        %% ============================================================
    
        if strcmpi(char(comparisonStage), 'POST_APJ_TRAIN')
    
            DebugHelper.recordBeamAPJQAgreement( ...
                slotIndex, ...
                beamGreedy, ...
                apjGreedy, ...
                qMAE, ...
                cosineSimilarity, ...
                qCorrelation, ...
                beamQMargin, ...
                apjQMargin ...
            );
    
        end
    
    
        %% ============================================================
        % 출력
        %% ============================================================
    
        fprintf('\n');
        fprintf('============================================================\n');
        fprintf('BEAM1 vs APJ Q-VECTOR COMPARISON\n');
        fprintf('============================================================\n');
    
        fprintf('  Slot                     : %d\n', ...
            slotIndex);
    
        fprintf('  Stage                    : %s\n', ...
            char(comparisonStage));
    
    
        fprintf('\n');
        fprintf('  [Policy Decision]\n');
    
        fprintf('    Beam1 Greedy Channel   : %d\n', ...
            beamGreedy);
    
        fprintf('    APJ Greedy Channel     : %d\n', ...
            apjGreedy);
    
        fprintf('    Greedy Match           : %s\n', ...
            DebugHelper.boolToString(greedyMatch));
    
    
        fprintf('\n');
        fprintf('  [Q-Vector Similarity]\n');
    
        fprintf('    MAE                    : %.6f\n', ...
            qMAE);
    
        fprintf('    RMSE                   : %.6f\n', ...
            qRMSE);
    
        fprintf('    Maximum Error          : %.6f\n', ...
            qMaxError);
    
        fprintf('    Cosine Similarity      : %.6f\n', ...
            cosineSimilarity);
    
        fprintf('    Pearson Correlation    : %.6f\n', ...
            qCorrelation);
    
    
        fprintf('\n');
        fprintf('  [Decision Margin]\n');
    
        fprintf('    Beam1 Best Q           : %.6f\n', ...
            beamBestQ);
    
        fprintf('    Beam1 Top-2 Margin     : %.6f\n', ...
            beamQMargin);
    
        fprintf('    APJ Best Q             : %.6f\n', ...
            apjBestQ);
    
        fprintf('    APJ Top-2 Margin       : %.6f\n', ...
            apjQMargin);
    
    
        fprintf('\n');
        fprintf('  [Per-Channel Q-Values]\n');
    
        fprintf('           Beam1 Q       APJ Q        Difference\n');
    
    
        for channelIndex = 1:numActions
    
            fprintf( ...
                '    CH %2d | %10.6f | %10.6f | %+10.6f', ...
                channelIndex, ...
                beamQ(channelIndex), ...
                apjQ(channelIndex), ...
                qDifference(channelIndex) ...
            );
    
            if channelIndex == beamGreedy && ...
               channelIndex == apjGreedy
    
                fprintf('  <-- BOTH GREEDY');
    
            elseif channelIndex == beamGreedy
    
                fprintf('  <-- BEAM GREEDY');
    
            elseif channelIndex == apjGreedy
    
                fprintf('  <-- APJ GREEDY');
    
            end
    
            fprintf('\n');
    
        end
    
        fprintf('============================================================\n');
    
    end
        

        function data = beamAPJQAgreementData(action, newData)
    
            persistent storedData
        
        
            %% ============================================================
            % Initialize
            %% ============================================================
        
            if isempty(storedData)
        
                storedData.Slot = [];
        
                storedData.BeamGreedy = [];
                storedData.APJGreedy = [];
        
                storedData.QMAE = [];
                storedData.Cosine = [];
                storedData.Correlation = [];
        
                storedData.BeamMargin = [];
                storedData.APJMargin = [];
        
            end
        
        
            %% ============================================================
            % Action
            %% ============================================================
        
            switch lower(action)
        
                case 'get'
        
                    data = storedData;
        
        
                case 'set'
        
                    storedData = newData;
        
                    data = storedData;
        
        
                case 'reset'
        
                    storedData.Slot = [];
        
                    storedData.BeamGreedy = [];
                    storedData.APJGreedy = [];
        
                    storedData.QMAE = [];
                    storedData.Cosine = [];
                    storedData.Correlation = [];
        
                    storedData.BeamMargin = [];
                    storedData.APJMargin = [];
        
                    data = storedData;
        
        
                otherwise
        
                    error( ...
                        'Unknown beamAPJQAgreementData action: %s', ...
                        action ...
                    );
        
            end
        
    end


        function recordBeamAPJQAgreement( ...
            slotIndex, ...
            beamGreedy, ...
            apjGreedy, ...
            qMAE, ...
            cosineSimilarity, ...
            qCorrelation, ...
            beamQMargin, ...
            apjQMargin)
    
    
        %% ============================================================
        % 기존 기록 가져오기
        %% ============================================================
    
        data = ...
            DebugHelper.beamAPJQAgreementData( ...
                'get', ...
                [] ...
            );
    
    
        %% ============================================================
        % 새 값 저장
        %% ============================================================
    
        data.Slot(end + 1) = ...
            slotIndex;
    
        data.BeamGreedy(end + 1) = ...
            beamGreedy;
    
        data.APJGreedy(end + 1) = ...
            apjGreedy;
    
        data.QMAE(end + 1) = ...
            qMAE;
    
        data.Cosine(end + 1) = ...
            cosineSimilarity;
    
        data.Correlation(end + 1) = ...
            qCorrelation;
    
        data.BeamMargin(end + 1) = ...
            beamQMargin;
    
        data.APJMargin(end + 1) = ...
            apjQMargin;
    
    
        DebugHelper.beamAPJQAgreementData( ...
            'set', ...
            data ...
        );
    
    
        %% ============================================================
        % Agreement
        %% ============================================================
    
        matchHistory = ...
            (data.BeamGreedy == data.APJGreedy);
    
    
        totalSamples = ...
            numel(matchHistory);
    
    
        overallAgreement = ...
            mean(matchHistory);
    
    
        recentWindow = ...
            min(100, totalSamples);
    
    
        recentAgreement = ...
            mean( ...
                matchHistory( ...
                    end-recentWindow+1:end ...
                ) ...
            );
    
    
        %% ============================================================
        % 출력
        %% ============================================================
    
        fprintf('\n');
        fprintf('============================================================\n');
        fprintf('BEAM1 - APJ GREEDY POLICY AGREEMENT\n');
        fprintf('============================================================\n');
    
        fprintf('  Slot                     : %d\n', ...
            slotIndex);
    
        fprintf('  Beam1 Greedy             : CH %d\n', ...
            beamGreedy);
    
        fprintf('  APJ Greedy               : CH %d\n', ...
            apjGreedy);
    
    
        if beamGreedy == apjGreedy
    
            fprintf('  Result                   : MATCH\n');
    
        else
    
            fprintf('  Result                   : MISMATCH\n');
    
        end
    
    
        fprintf('\n');
        fprintf('  [Cumulative]\n');
    
        fprintf('    Samples                : %d\n', ...
            totalSamples);
    
        fprintf('    Greedy Agreement       : %.2f %%\n', ...
            overallAgreement * 100);
    
        fprintf('    Recent Agreement (%3d): %.2f %%\n', ...
            recentWindow, ...
            recentAgreement * 100);
    
        fprintf('============================================================\n');
    
    end
        function printBeamAPJQAgreementSummary()

            data = ...
                DebugHelper.beamAPJQAgreementData( ...
                    'get', ...
                    [] ...
                );
        
        
            %% ============================================================
            % 데이터 확인
            %% ============================================================
        
            if isempty(data.Slot)
        
                fprintf('\n');
                fprintf('============================================================\n');
                fprintf('BEAM1 - APJ Q-POLICY SUMMARY\n');
                fprintf('============================================================\n');
                fprintf('  No Q-comparison samples recorded.\n');
                fprintf('============================================================\n');
        
                return;
        
            end
        
        
            %% ============================================================
            % Match
            %% ============================================================
        
            matchHistory = ...
                (data.BeamGreedy == data.APJGreedy);
        
        
            totalSamples = ...
                numel(matchHistory);
        
        
            correctCount = ...
                sum(matchHistory);
        
        
            mismatchCount = ...
                totalSamples - correctCount;
        
        
            overallAgreement = ...
                mean(matchHistory);
        
        
            %% ============================================================
            % Recent 100
            %% ============================================================
        
            recentWindow = ...
                min(100, totalSamples);
        
        
            recentIndices = ...
                totalSamples-recentWindow+1 : totalSamples;
        
        
            recentAgreement = ...
                mean(matchHistory(recentIndices));
        
        
            %% ============================================================
            % Similarity
            %% ============================================================
        
            averageQMAE = ...
                mean(data.QMAE, 'omitnan');
        
        
            averageCosine = ...
                mean(data.Cosine, 'omitnan');
        
        
            averageCorrelation = ...
                mean(data.Correlation, 'omitnan');
        
        
            averageBeamMargin = ...
                mean(data.BeamMargin, 'omitnan');
        
        
            averageAPJMargin = ...
                mean(data.APJMargin, 'omitnan');
        
        
            %% ============================================================
            % Recent Similarity
            %% ============================================================
        
            recentQMAE = ...
                mean( ...
                    data.QMAE(recentIndices), ...
                    'omitnan' ...
                );
        
        
            recentCosine = ...
                mean( ...
                    data.Cosine(recentIndices), ...
                    'omitnan' ...
                );
        
        
            recentCorrelation = ...
                mean( ...
                    data.Correlation(recentIndices), ...
                    'omitnan' ...
                );
        
        
            %% ============================================================
            % 출력
            %% ============================================================
        
            fprintf('\n');
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('BEAM1 - APJ Q-POLICY SHADOWING SUMMARY\n');
            fprintf('============================================================\n');
        
            fprintf('  Comparison Stage         : POST_APJ_TRAIN\n');
        
            fprintf('  Number of Samples        : %d\n', ...
                totalSamples);
        
            fprintf('  First Slot               : %d\n', ...
                data.Slot(1));
        
            fprintf('  Last Slot                : %d\n', ...
                data.Slot(end));
        
        
            fprintf('\n');
            fprintf('  [Greedy Policy Agreement]\n');
        
            fprintf('    Matched                : %d\n', ...
                correctCount);
        
            fprintf('    Mismatched             : %d\n', ...
                mismatchCount);
        
            fprintf('    Overall Agreement      : %.2f %%\n', ...
                overallAgreement * 100);
        
            fprintf('    Recent Agreement (%3d): %.2f %%\n', ...
                recentWindow, ...
                recentAgreement * 100);
        
        
            fprintf('\n');
            fprintf('  [Q-Vector Similarity - Overall]\n');
        
            fprintf('    Average Q-MAE          : %.6f\n', ...
                averageQMAE);
        
            fprintf('    Average Cosine         : %.6f\n', ...
                averageCosine);
        
            fprintf('    Average Pearson Corr.  : %.6f\n', ...
                averageCorrelation);
        
        
            fprintf('\n');
            fprintf('  [Q-Vector Similarity - Recent %d]\n', ...
                recentWindow);
        
            fprintf('    Average Q-MAE          : %.6f\n', ...
                recentQMAE);
        
            fprintf('    Average Cosine         : %.6f\n', ...
                recentCosine);
        
            fprintf('    Average Pearson Corr.  : %.6f\n', ...
                recentCorrelation);
        
        
            fprintf('\n');
            fprintf('  [Decision Margin]\n');
        
            fprintf('    Avg Beam1 Top-2 Margin : %.6f\n', ...
                averageBeamMargin);
        
            fprintf('    Avg APJ Top-2 Margin   : %.6f\n', ...
                averageAPJMargin);
        
        
            fprintf('\n');
            fprintf('  Interpretation:\n');
        
            fprintf('    Greedy agreement measures exact policy-action agreement.\n');
        
            fprintf('    Q-vector similarity measures value-function similarity.\n');
        
            fprintf('============================================================\n');
        
        end


        % 평가 함수 (예: DebugHelper.recordAPJPrediction 확장, 혹은 별도 함수)
        function recordAPJTopKAccuracy(slotIndex, predictedQValues, actualChannel)
            persistent top1Count top2Count top3Count top4Count totalCount
        
            if isempty(totalCount)
                top1Count = 0; top2Count = 0; top3Count = 0; top4Count = 0; totalCount = 0;
            end
        
            if isempty(predictedQValues) || isempty(actualChannel)
                return;
            end
        
            [~, sortedChannels] = sort(predictedQValues, 'descend');  % 1등부터 순위
        
            totalCount = totalCount + 1;
            if any(sortedChannels(1)   == actualChannel), top1Count = top1Count + 1; end
            if any(sortedChannels(1:2) == actualChannel), top2Count = top2Count + 1; end
            if any(sortedChannels(1:3) == actualChannel), top3Count = top3Count + 1; end
            if any(sortedChannels(1:4) == actualChannel), top4Count = top4Count + 1; end
        
            fprintf("  Top-1: %.2f%% | Top-2: %.2f%% | Top-3: %.2f%% | Top-4: %.2f%%\n", ...
                100*top1Count/totalCount, 100*top2Count/totalCount, ...
                100*top3Count/totalCount, 100*top4Count/totalCount);
        end
    
    
    
    end
end