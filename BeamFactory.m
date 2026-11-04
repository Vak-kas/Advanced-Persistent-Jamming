classdef BeamFactory
    methods (Static)

        %% ========== 빔 전체 생성 ==========
        function beams = createBeams( ...
                numBeams, ...
                maxBeamFootprintDiameter, ...
                beamRadius, ...
                beamSpacing, ...
                beamMaxGain_dBi, ...
                beam3dBWidth_deg, ...
                beamEIRPDensity_dBW_per_MHz, ...
                channelBandwidth_Hz)

            % =====================================================
            % Beam 배치 가능 최대 반경
            %
            % Beam 중심이 이 반경 이내에 있어야
            % Beam 전체가 Satellite coverage 내부에 포함됨
            % =====================================================
            maxBeamCenterRadius = ...
                (maxBeamFootprintDiameter / 2) - beamRadius;


            % =====================================================
            % Beam Tx Power 계산
            % =====================================================
            beamTxPower_dBm = ...
                BeamFactory.calculateBeamTxPower_dBm( ...
                    beamEIRPDensity_dBW_per_MHz, ...
                    channelBandwidth_Hz, ...
                    beamMaxGain_dBi ...
                );


            % =====================================================
            % Hexagonal Beam 중심 좌표 생성
            % =====================================================
            beamCenters = ...
                BeamFactory.generateHexagonalBeamCenters( ...
                    numBeams, ...
                    beamSpacing, ...
                    maxBeamCenterRadius ...
                );


            % =====================================================
            % Beam 배열 생성
            % =====================================================
            beams = Beam.empty(0, numBeams);

            for beamIndex = 1:numBeams

                associatedUTId = beamIndex;

                beams(beamIndex) = Beam( ...
                    beamIndex, ...
                    beamCenters(beamIndex, :), ...
                    beamRadius, ...
                    beamTxPower_dBm, ...
                    beamMaxGain_dBi, ...
                    beam3dBWidth_deg, ...
                    associatedUTId ...
                );

            end
        end



        %% ========== Hexagonal Beam 중심 좌표 생성 ==========
        function beamCenters = generateHexagonalBeamCenters( ...
                numBeams, ...
                beamSpacing, ...
                maxBeamCenterRadius)

            % =====================================================
            % Hexagonal lattice 기반 Beam 배치
            %
            % Beam 1은 중앙 [0, 0, 0]
            %
            % 이후 중앙에서 가까운 위치부터 순서대로 선택
            %
            % 완전한 ring 기준 Beam 개수:
            %
            % Ring 0 : 1
            % Ring 1 : 6
            % Ring 2 : 12
            % Ring 3 : 18
            %
            % 누적:
            % 1, 7, 19, 37, 61, 91, ...
            % =====================================================


            % -----------------------------------------------------
            % 필요한 ring 개수 계산
            %
            % 충분히 넉넉하게 생성한 뒤
            % 중심 거리 기준으로 필요한 개수만 선택
            % -----------------------------------------------------
            ringIndex = 0;

            while (1 + 3 * ringIndex * (ringIndex + 1)) < numBeams
                ringIndex = ringIndex + 1;
            end


            % 혹시 경계 잘림 때문에 부족할 수 있으므로
            % 한 ring 여유 있게 생성
            maxRing = ringIndex + 1;


            % 최대 candidate 개수
            maxCandidates = ...
                1 + 3 * maxRing * (maxRing + 1);

            candidateCenters = zeros(maxCandidates, 3);

            candidateCount = 0;


            % =====================================================
            % Axial coordinate 기반 Hexagonal lattice 생성
            % =====================================================
            for q = -maxRing:maxRing

                for r = -maxRing:maxRing

                    % 세 번째 cube coordinate
                    s = -q - r;

                    % Hexagonal ring 범위 검사
                    if max([abs(q), abs(r), abs(s)]) > maxRing
                        continue;
                    end


                    % -------------------------------------------------
                    % Axial coordinate -> Cartesian coordinate
                    %
                    % 인접 Beam 중심 간 거리가 정확히 beamSpacing이
                    % 되도록 변환
                    %
                    % x = d * (q + r/2)
                    % y = d * sqrt(3)/2 * r
                    % -------------------------------------------------
                    x = beamSpacing * (q + r / 2);

                    y = beamSpacing ...
                        * (sqrt(3) / 2) ...
                        * r;

                    z = 0;


                    % Satellite coverage 내부 여부 검사
                    centerDistance = sqrt(x^2 + y^2);

                    if centerDistance > maxBeamCenterRadius
                        continue;
                    end


                    candidateCount = candidateCount + 1;

                    candidateCenters(candidateCount, :) = ...
                        [x, y, z];

                end
            end


            % 사용하지 않은 preallocation 영역 제거
            candidateCenters = ...
                candidateCenters(1:candidateCount, :);


            % =====================================================
            % Beam을 충분히 배치할 수 있는지 검사
            % =====================================================
            if candidateCount < numBeams

                error( ...
                    "BeamFactory:InsufficientCoverage", ...
                    [ ...
                    "현재 coverage 내부에 Beam %d개를 배치할 수 없습니다.\n" ...
                    "Available Beam Centers : %d\n" ...
                    "Beam Spacing           : %.2f km\n" ...
                    "Max Center Radius      : %.2f km" ...
                    ], ...
                    numBeams, ...
                    candidateCount, ...
                    beamSpacing / 1e3, ...
                    maxBeamCenterRadius / 1e3 ...
                );

            end


            % =====================================================
            % 중심으로부터 거리 계산
            % =====================================================
            centerDistances = sqrt( ...
                candidateCenters(:, 1).^2 ...
                + candidateCenters(:, 2).^2 ...
            );


            % =====================================================
            % 거리 기준 정렬
            %
            % 동일 거리에서는 atan2 각도 기준으로 정렬해서
            % 실행할 때마다 Beam ID가 동일하게 유지되도록 함
            % =====================================================
            angles = atan2( ...
                candidateCenters(:, 2), ...
                candidateCenters(:, 1) ...
            );


            sortingMatrix = [
                centerDistances, ...
                angles ...
            ];

            [~, sortedIndices] = ...
                sortrows(sortingMatrix, [1 2]);


            candidateCenters = ...
                candidateCenters(sortedIndices, :);


            % =====================================================
            % 필요한 Beam 개수만 선택
            % =====================================================
            beamCenters = ...
                candidateCenters(1:numBeams, :);

        end



        %% ========== EIRP Density 기반 Beam Tx Power 계산 ==========
        function beamTxPower_dBm = ...
                calculateBeamTxPower_dBm( ...
                    beamEIRPDensity_dBW_per_MHz, ...
                    channelBandwidth_Hz, ...
                    beamMaxGain_dBi)

            % Hz -> MHz
            channelBandwidth_MHz = ...
                channelBandwidth_Hz / 1e6;


            % -----------------------------------------------------
            % EIRP Density -> EIRP
            %
            % EIRP[dBW]
            % =
            % EIRP Density[dBW/MHz]
            % + 10log10(BW[MHz])
            % -----------------------------------------------------
            beamEIRP_dBW = ...
                beamEIRPDensity_dBW_per_MHz ...
                + 10 * log10(channelBandwidth_MHz);


            % -----------------------------------------------------
            % EIRP = Tx Power + Antenna Gain
            %
            % Tx Power[dBW]
            % =
            % EIRP[dBW] - Gain[dBi]
            % -----------------------------------------------------
            beamTxPower_dBW = ...
                beamEIRP_dBW ...
                - beamMaxGain_dBi;


            % dBW -> dBm
            beamTxPower_dBm = ...
                beamTxPower_dBW + 30;

        end

    end
end