classdef FigureHelper
    methods (Static)

        % ============================================================
        % 전체 시스템 배치 출력
        % ============================================================
        function plotSystemDeployment( ...
                SatelliteNode, ...
                Beams, ...
                UTs, ...
                APJNode, ...
                maxBeamFootprintDiameter)

            %% =====================================================
            % Figure 생성
            % ======================================================
            figure( ...
                'Name', 'System Deployment', ...
                'NumberTitle', 'off', ...
                'Units', 'normalized', ...
                'Position', [0.03 0.05 0.88 0.88] ...
            );

            hold on;
            grid on;
            axis equal;
            box on;

            ax = gca;

            ax.FontSize = 12;
            ax.LineWidth = 1;
            ax.TickDir = 'out';

            % Grid를 너무 진하지 않게
            ax.GridAlpha = 0.15;
            ax.MinorGridAlpha = 0.10;

            theta = linspace(0, 2*pi, 500);


            %% =====================================================
            % Satellite Beam Footprint
            % ======================================================
            footprintRadius_km = ...
                (maxBeamFootprintDiameter / 2) / 1e3;

            footprintX = ...
                footprintRadius_km * cos(theta);

            footprintY = ...
                footprintRadius_km * sin(theta);

            hFootprint = plot( ...
                footprintX, ...
                footprintY, ...
                'k--', ...
                'LineWidth', 2 ...
            );


            %% =====================================================
            % Beam 영역
            % ======================================================
            hBeam = [];
            hBeamCenter = [];

            for beamIndex = 1:numel(Beams)

                beam = Beams(beamIndex);

                centerX_km = ...
                    beam.CenterPosition(1) / 1e3;

                centerY_km = ...
                    beam.CenterPosition(2) / 1e3;

                radius_km = ...
                    beam.Radius / 1e3;


                % Beam 원
                beamX = ...
                    centerX_km ...
                    + radius_km * cos(theta);

                beamY = ...
                    centerY_km ...
                    + radius_km * sin(theta);


                % Beam 경계
                currentBeam = plot( ...
                    beamX, ...
                    beamY, ...
                    'b-', ...
                    'LineWidth', 1.0 ...
                );


                % Beam 중심
                currentCenter = plot( ...
                    centerX_km, ...
                    centerY_km, ...
                    'bx', ...
                    'MarkerSize', 8, ...
                    'LineWidth', 1.5 ...
                );


                % Legend는 첫 번째 Beam만 사용
                if beamIndex == 1
                    hBeam = currentBeam;
                    hBeamCenter = currentCenter;
                end

            end


            %% =====================================================
            % UT 위치
            % ======================================================
            hUT = [];
            hTargetUT = [];

            for utIndex = 1:numel(UTs)

                ut = UTs(utIndex);

                utX_km = ...
                    ut.Position(1) / 1e3;

                utY_km = ...
                    ut.Position(2) / 1e3;


                % Target UT
                if ut.IsTarget

                    hTargetUT = plot( ...
                        utX_km, ...
                        utY_km, ...
                        'r*', ...
                        'MarkerSize', 13, ...
                        'LineWidth', 2 ...
                    );

                % Normal UT
                else

                    currentUT = plot( ...
                        utX_km, ...
                        utY_km, ...
                        'ko', ...
                        'MarkerSize', 6, ...
                        'MarkerFaceColor', 'w', ...
                        'LineWidth', 1.2 ...
                    );

                    % Legend는 첫 번째 Normal UT만 사용
                    if isempty(hUT)
                        hUT = currentUT;
                    end

                end

            end


            %% =====================================================
            % APJ 위치
            % ======================================================
            hAPJ = [];

            if ~isempty(APJNode)

                apjX_km = ...
                    APJNode.Position(1) / 1e3;

                apjY_km = ...
                    APJNode.Position(2) / 1e3;


                hAPJ = plot( ...
                    apjX_km, ...
                    apjY_km, ...
                    'md', ...
                    'MarkerSize', 10, ...
                    'MarkerFaceColor', 'm', ...
                    'LineWidth', 1.5 ...
                );


                %% -------------------------------------------------
                % Target UT ↔ APJ 연결선
                % --------------------------------------------------
                targetUT = ...
                    UTs(APJNode.TargetUTId);

                targetX_km = ...
                    targetUT.Position(1) / 1e3;

                targetY_km = ...
                    targetUT.Position(2) / 1e3;


                plot( ...
                    [targetX_km apjX_km], ...
                    [targetY_km apjY_km], ...
                    'm--', ...
                    'LineWidth', 1.2, ...
                    'HandleVisibility', 'off' ...
                );

            end


            %% =====================================================
            % Satellite Ground Projection
            % ======================================================
            satelliteX_km = ...
                SatelliteNode.Position(1) / 1e3;

            satelliteY_km = ...
                SatelliteNode.Position(2) / 1e3;


            hSatellite = plot( ...
                satelliteX_km, ...
                satelliteY_km, ...
                'ks', ...
                'MarkerSize', 11, ...
                'MarkerFaceColor', 'k', ...
                'LineWidth', 1.2 ...
            );


            %% =====================================================
            % Axis 설정
            % ======================================================
            margin_km = 30;

            xlim([ ...
                -footprintRadius_km - margin_km, ...
                 footprintRadius_km + margin_km ...
            ]);

            ylim([ ...
                -footprintRadius_km - margin_km, ...
                 footprintRadius_km + margin_km ...
            ]);


            xlabel( ...
                'X Position [km]', ...
                'FontSize', 13 ...
            );

            ylabel( ...
                'Y Position [km]', ...
                'FontSize', 13 ...
            );


            title( ...
                'Satellite Beam and Ground Node Deployment', ...
                'FontSize', 15, ...
                'FontWeight', 'bold' ...
            );


            %% =====================================================
            % Legend 생성
            % ======================================================
            legendHandles = [];
            legendLabels = {};


            % Beam Footprint
            legendHandles(end+1) = ...
                hFootprint;

            legendLabels{end+1} = ...
                'Beam footprint boundary';


            % Beam
            if ~isempty(hBeam)

                legendHandles(end+1) = ...
                    hBeam;

                legendLabels{end+1} = ...
                    'Beam';

            end


            % Beam Center
            if ~isempty(hBeamCenter)

                legendHandles(end+1) = ...
                    hBeamCenter;

                legendLabels{end+1} = ...
                    'Beam center';

            end


            % Normal UT
            if ~isempty(hUT)

                legendHandles(end+1) = ...
                    hUT;

                legendLabels{end+1} = ...
                    'UT';

            end


            % Target UT
            if ~isempty(hTargetUT)

                legendHandles(end+1) = ...
                    hTargetUT;

                legendLabels{end+1} = ...
                    'Target UT';

            end


            % APJ
            if ~isempty(hAPJ)

                legendHandles(end+1) = ...
                    hAPJ;

                legendLabels{end+1} = ...
                    'APJ';

            end


            % Satellite
            legendHandles(end+1) = ...
                hSatellite;

            legendLabels{end+1} = ...
                'Satellite ground projection';


            legend( ...
                legendHandles, ...
                legendLabels, ...
                'Location', 'eastoutside', ...
                'FontSize', 10 ...
            );


            hold off;

        end


        % ============================================================
        % Beam1(Target UT) 실시간 성공률(ACK ratio) 출력
        % ------------------------------------------------------------
        % 호출 예 (TimeSlot.run 등에서 한 줄만 추가):
        %   FigureHelper.plotBeam1SuccessRate(slotIndex, actualTargetACK);
        %
        % persistent 변수로 Figure/버퍼 상태를 유지하므로,
        % 매 슬롯 이 한 줄만 호출하면 알아서 창을 만들고 갱신합니다.
        % ============================================================
        function plotBeam1SuccessRate(slotIndex, isACK, shortWindow, emaSpan)
            % 하위 호환용 wrapper — 내부적으로 plotSuccessRate 호출
            if nargin < 3, shortWindow = []; end
            if nargin < 4, emaSpan = []; end
            FigureHelper.plotSuccessRate(slotIndex, isACK, 'Beam1 (Target UT)', shortWindow, emaSpan);
        end

        % ============================================================
        % 임의의 지표(0~1 사이 값)에 대한 실시간 성공률 플롯 (범용)
        % ------------------------------------------------------------
        % 호출 예:
        %   FigureHelper.plotSuccessRate(slotIndex, actualTargetACK, 'Beam1 (Target UT)');
        %   FigureHelper.plotSuccessRate(slotIndex, successRatio, 'All UTs (Aggregate)');
        %
        % seriesName마다 별도 Figure/버퍼 상태를 유지하므로(내부적으로
        % containers.Map 사용), 같은 파일에서 여러 지표를 동시에
        % 각자의 창에 실시간으로 그릴 수 있습니다.
        % ============================================================
        function plotSuccessRate(slotIndex, value, seriesName, shortWindow, emaSpan)

            persistent stateMap

            if nargin < 4 || isempty(shortWindow)
                shortWindow = 100;
            end
            if nargin < 5 || isempty(emaSpan)
                emaSpan = 200;
            end
            alpha = 2 / (emaSpan + 1);

            if isempty(stateMap)
                stateMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end

            %% =====================================================
            % 이 seriesName의 Figure 최초 1회 생성
            % ======================================================
            needsInit = ~isKey(stateMap, seriesName);
            if ~needsInit
                s = stateMap(seriesName);
                needsInit = ~isvalid(s.figHandle);
            end

            if needsInit
                s = struct();

                s.figHandle = figure( ...
                    'Name', sprintf('%s 실시간 성공률', seriesName), ...
                    'NumberTitle', 'off' ...
                );

                s.axHandle = axes(s.figHandle);
                hold(s.axHandle, 'on');
                grid(s.axHandle, 'on');
                s.axHandle.GridAlpha = 0.15;

                ylim(s.axHandle, [0 1]);
                xlabel(s.axHandle, 'Time Slot', 'FontSize', 12);
                ylabel(s.axHandle, sprintf('%s Ratio', seriesName), 'FontSize', 12);
                title(s.axHandle, ...
                    sprintf('%s 실시간 성공률', seriesName), ...
                    'FontSize', 14, 'FontWeight', 'bold');

                s.rawLine = animatedline(s.axHandle, ...
                    'LineStyle', 'none', ...
                    'Marker', '.', ...
                    'MarkerSize', 4, ...
                    'Color', [0.85 0.85 0.85], ...
                    'DisplayName', 'Per-slot value');

                % 노이즈 많은 실시간 곡선 → 회색, 얇게
                s.shortLine = animatedline(s.axHandle, ...
                    'Color', [0.55 0.55 0.55], ...
                    'LineWidth', 1.0, ...
                    'DisplayName', sprintf('Noisy rolling (window=%d)', shortWindow));

                % 매끈한 평균 곡선 → 파란색, 굵게 (EMA)
                s.longLine = animatedline(s.axHandle, ...
                    'Color', [0.00 0.30 0.80], ...
                    'LineWidth', 2.2, ...
                    'DisplayName', sprintf('Smoothed EMA (span=%d)', emaSpan));

                legend(s.axHandle, 'Location', 'southeast');

                s.history = [];
                s.emaValue = [];

                stateMap(seriesName) = s;
            end

            s = stateMap(seriesName);

            %% =====================================================
            % 짧은 윈도우(노이즈) 갱신
            % ======================================================
            s.history(end+1) = double(value); %#ok<AGROW>
            n = numel(s.history);
            shortRatio = mean(s.history(max(1, n-shortWindow+1):n));

            addpoints(s.rawLine, slotIndex, double(value));
            addpoints(s.shortLine, slotIndex, shortRatio);

            %% =====================================================
            % EMA 갱신 — 첫 슬롯부터 바로 값이 생김 (대기 없음)
            % ======================================================
            if isempty(s.emaValue)
                s.emaValue = double(value);
            else
                s.emaValue = alpha * double(value) + (1 - alpha) * s.emaValue;
            end
            addpoints(s.longLine, slotIndex, s.emaValue);

            xlim(s.axHandle, [1, max(slotIndex, shortWindow)]);

            if mod(slotIndex, 5) == 0 || slotIndex == 1
                drawnow limitrate;
            end

            stateMap(seriesName) = s;

        end


        function plotBeamAPJGreedyAgreement()

            data = ...
                DebugHelper.beamAPJQAgreementData( ...
                    'get', ...
                    [] ...
                );
        
        
            if isempty(data.Slot)
                return;
            end
        
        
            matchHistory = ...
                double( ...
                    data.BeamGreedy == data.APJGreedy ...
                );
        
        
            windowSize = 100;
        
        
            movingAgreement = ...
                movmean( ...
                    matchHistory, ...
                    [windowSize-1 0] ...
                );
        
        
            figure;
        
            plot( ...
                data.Slot, ...
                movingAgreement * 100, ...
                'LineWidth', ...
                1.5 ...
            );
        
        
            xlabel('Time Slot');
        
            ylabel('Greedy Agreement (%)');
        
            title( ...
                sprintf( ...
                    'Beam1-APJ Greedy Policy Agreement (Moving Window = %d)', ...
                    windowSize ...
                ) ...
            );
        
            ylim([0 100]);
        
            grid on;
        
        end
    
        function plotBeamAPJQMAE()
        
            data = ...
                DebugHelper.beamAPJQAgreementData( ...
                    'get', ...
                    [] ...
                );
        
        
            if isempty(data.Slot)
                return;
            end
        
        
            windowSize = 100;
        
        
            movingQMAE = ...
                movmean( ...
                    data.QMAE, ...
                    [windowSize-1 0] ...
                );
        
        
            figure;
        
            plot( ...
                data.Slot, ...
                movingQMAE, ...
                'LineWidth', ...
                1.5 ...
            );
        
        
            xlabel('Time Slot');
        
            ylabel('Q-Value MAE');
        
            title( ...
                sprintf( ...
                    'Beam1-APJ Q-Value MAE (Moving Window = %d)', ...
                    windowSize ...
                ) ...
            );
        
            grid on;
        
        end
    

        function plotBeamAPJCosineSimilarity()

            data = ...
                DebugHelper.beamAPJQAgreementData( ...
                    'get', ...
                    [] ...
                );
        
        
            if isempty(data.Slot)
                return;
            end
        
        
            windowSize = 100;
        
        
            movingCosine = ...
                movmean( ...
                    data.Cosine, ...
                    [windowSize-1 0], ...
                    'omitnan' ...
                );
        
        
            figure;
        
            plot( ...
                data.Slot, ...
                movingCosine, ...
                'LineWidth', ...
                1.5 ...
            );
        
        
            xlabel('Time Slot');
        
            ylabel('Cosine Similarity');
        
            title( ...
                sprintf( ...
                    'Beam1-APJ Q-Vector Cosine Similarity (Moving Window = %d)', ...
                    windowSize ...
                ) ...
            );
        
            ylim([0 1]);
        
            grid on;
        
        end
    
        function plotBeamAPJQCorrelation()
    
        data = ...
            DebugHelper.beamAPJQAgreementData( ...
                'get', ...
                [] ...
            );
    
    
        if isempty(data.Slot)
            return;
        end
    
    
        windowSize = 100;
    
    
        movingCorrelation = ...
            movmean( ...
                data.Correlation, ...
                [windowSize-1 0], ...
                'omitnan' ...
            );
    
    
        figure;
    
        plot( ...
            data.Slot, ...
            movingCorrelation, ...
            'LineWidth', ...
            1.5 ...
        );
    
    
        xlabel('Time Slot');
    
        ylabel('Pearson Correlation');
    
        title( ...
            sprintf( ...
                'Beam1-APJ Q-Vector Correlation (Moving Window = %d)', ...
                windowSize ...
            ) ...
        );
    
        ylim([-1 1]);
    
        grid on;
    
        end

        %% ========== APJ Prediction Accuracy 추이 그래프 ==========
        % [수정] numChannels를 옵션 인자로 받도록 변경.
        % 기존 코드는 random baseline을 100/max(actual)로 계산했는데,
        % 이는 "실제 관측된 채널 인덱스의 최댓값"에 의존하는 값이라
        % 특정 채널(예: 마지막 채널)이 한 번도 선택되지 않으면
        % baseline 자체가 실제 채널 수보다 작게(즉, 잘못) 계산되는
        % 문제가 있었음. numChannels를 명시적으로 넘기면 그 값을 쓰고,
        % 넘기지 않으면 기존 동작(max(actual))으로 하위 호환.
        function plotAPJAccuracyTrend(windowSize, numChannels)

            if nargin < 1 || isempty(windowSize)
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

            if nargin < 2 || isempty(numChannels)
                numChannels = max(actual);   % 하위 호환 (기존 동작)
            end

            correctHistory = double(predicted == actual);

            % 누적 정확도 (slot 1부터 현재까지)
            cumulativeAccuracy = cumsum(correctHistory) ./ (1:numel(correctHistory));

            % 이동평균(rolling) 정확도 — 최근 windowSize 슬롯 기준
            rollingAccuracy = movmean(correctHistory, [windowSize-1, 0], 'omitnan');

            figure;
            plot(slots, cumulativeAccuracy * 100, 'LineWidth', 1.2);
            hold on;
            plot(slots, rollingAccuracy * 100, 'LineWidth', 1.2);
            yline(100 / numChannels, '--', 'Random Baseline');
            hold off;

            xlabel('Time Slot');
            ylabel('Accuracy (%)');
            title('APJ Channel Prediction Accuracy over Time');
            legend('Cumulative Accuracy', sprintf('Rolling Accuracy (window=%d)', windowSize), 'Location', 'southeast');
            grid on;
            ylim([0 100]);
            xlim([slots(1), slots(end)]);

        end

        %% ========== Target UT 성공률(ACK Rate) 단독 그래프 ==========
        % plotTargetUTThroughput과 같은 데이터(DebugHelper.TargetUTStorage)를
        % 쓰지만, SINR 없이 성공률(ACK Rate)만 단독 Figure로 그린다.
        % TimeSlot.m / TimeSlotD.m / TimeSlotDE.m / TimeSlotS.m 전부
        % DebugHelper.recordTargetUTOutcome을 동일하게 호출하므로,
        % 어느 파이프라인을 돌렸든 그대로 호출하면 된다.
        function plotTargetUTSuccessRate(windowSize)

            if nargin < 1 || isempty(windowSize)
                windowSize = 100;
            end

            data = DebugHelper.TargetUTStorage('get', []);

            if isempty(data.slots)
                fprintf('기록된 Target UT 데이터가 없습니다.\n');
                return;
            end

            slots = data.slots;
            ackHistory = double(data.isACK);

            rollingACKRate = movmean(ackHistory, [windowSize-1, 0], 'omitnan');
            cumulativeACKRate = cumsum(ackHistory, 'omitnan') ./ (1:numel(ackHistory));

            attackStartIdx = find(data.isAttackPhase, 1);

            colorCumulative = [0.00 0.30 0.80];
            colorRolling = [0.8500 0.0980 0.0980];

            figure;
            plot(slots, cumulativeACKRate * 100, 'LineWidth', 1.2, 'Color', colorCumulative);
            hold on;
            plot(slots, rollingACKRate * 100, 'LineWidth', 1.2, 'Color', colorRolling);
            if ~isempty(attackStartIdx)
                xline(slots(attackStartIdx), '--r', 'Attack Start', 'LineWidth', 1.2);
            end
            hold off;
            xlabel('Time Slot');
            ylabel('Success Rate (%)');
            title('Target UT Success Rate (ACK Rate) over Time');
            legend('Cumulative', sprintf('Rolling (window=%d)', windowSize), 'Location', 'southwest');
            grid on;
            ylim([0 100]);
            xlim([slots(1), slots(end)]);

        end


        %% ========== Target UT ACK Rate 추이 그래프 (ACK+SINR 결합) ==========
        % [수정 사항]
        %   1. movmean에 'omitnan' 추가 — SINR_dB에 NaN이 섞여도
        %      그 지점만 건너뛰고 이후 rolling이 다시 계산되도록 함
        %      (기존엔 NaN 하나가 이후 윈도우 전체를 영구히 오염시킴).
        %   2. xlim을 데이터 전체 범위로 명시적으로 고정 — MATLAB이
        %      Y값 NaN인 구간을 축 자동범위 계산에서 제외해버려
        %      그래프가 중간에 잘려 보이던 문제 해결.
        %   3. Attack-Phase 전용 rolling 라인 추가 — 기존 rolling은
        %      Attack Start 직후 windowSize(예: 100) 슬롯 동안 정찰
        %      구간의 값까지 창(window)에 섞어서 평균내므로, 공격
        %      효과가 희석되어 보임. Attack Start 시점부터 새로
        %      시작하는(정찰 데이터가 절대 섞이지 않는) rolling을
        %      별도 라인으로 추가해서 "순수 공격 구간 추이"를 바로
        %      볼 수 있게 함.
        %   4. SINR 서브플롯의 placeholder yline(0)을 옵션 인자
        %      sinrThreshold_dB로 교체 — 실제 판정 임계값을 넘기면
        %      그 값으로 기준선을 그리고, 안 넘기면 기준선 생략.
        function plotTargetUTThroughput(windowSize, sinrThreshold_dB)

            if nargin < 1 || isempty(windowSize)
                windowSize = 100;
            end
            if nargin < 2
                sinrThreshold_dB = [];
            end

            data = DebugHelper.TargetUTStorage('get', []);

            if isempty(data.slots)
                fprintf('기록된 Target UT 데이터가 없습니다.\n');
                return;
            end

            slots = data.slots;
            ackHistory = double(data.isACK);
            sinrHistory = double(data.SINR_dB);

            % ---- 전체 구간 rolling (기존과 동일한 정의, omitnan만 추가) ----
            rollingACKRate = movmean(ackHistory, [windowSize-1, 0], 'omitnan');
            cumulativeACKRate = cumsum(ackHistory, 'omitnan') ./ (1:numel(ackHistory));
            rollingSINR = movmean(sinrHistory, [windowSize-1, 0], 'omitnan');

            attackStartIdx = find(data.isAttackPhase, 1);

            % 색상: Cumulative = 파랑, Rolling(window=100) = 빨강
            colorCumulative = [0.00 0.30 0.80];
            colorRollingFull = [0.8500 0.0980 0.0980]; % 빨강

            figure;

            % ======================= ACK Rate =======================
            subplot(2,1,1);
            plot(slots, cumulativeACKRate * 100, 'LineWidth', 1.2, 'Color', colorCumulative);
            hold on;
            plot(slots, rollingACKRate * 100, 'LineWidth', 1.2, 'Color', colorRollingFull);
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
            xlim([slots(1), slots(end)]);

            % ======================== SINR ===========================
            subplot(2,1,2);
            plot(slots, rollingSINR, 'LineWidth', 1.2, 'Color', colorRollingFull);
            hold on;
            if ~isempty(sinrThreshold_dB)
                yline(sinrThreshold_dB, ':', sprintf('SINR Threshold (%.1f dB)', sinrThreshold_dB));
            end
            if ~isempty(attackStartIdx)
                xline(slots(attackStartIdx), '--r', 'Attack Start', 'LineWidth', 1.2);
            end
            hold off;
            xlabel('Time Slot');
            ylabel('SINR (dB)');
            title(sprintf('Target UT SINR over Time (Rolling window=%d)', windowSize));
            legend(sprintf('Rolling (window=%d)', windowSize), 'Location', 'best');
            grid on;
            xlim([slots(1), slots(end)]);

            % ---- 진단: SINR_dB 원본 NaN 패턴을 슬롯 단위로 정확히 짚어줌.
            % omitnan을 적용해도 특정 구간 이후로 rolling이 안 그려진다면,
            % 그건 그래프 문제가 아니라 원본 SINR_dB 자체가 그 구간부터
            % 계속 NaN이라는 뜻 — 이 블록이 "어느 슬롯부터, 몇 개 연속으로"
            % NaN인지 콘솔에 정확히 찍어줘서 UT.m 쪽 원인 추적을 돕는다.
            isNanSINR = isnan(sinrHistory);
            if any(isNanSINR)
                nanRatio = mean(isNanSINR) * 100;
                firstNanIdx = find(isNanSINR, 1, 'first');

                % 마지막으로 "NaN이 아닌" 유효 슬롯 위치
                lastValidIdx = find(~isNanSINR, 1, 'last');

                % firstNanIdx부터 끝까지 전부 NaN인지(=완전히 끊겨서
                % 회복이 안 되는 케이스)를 확인
                isPermanentlyBroken = all(isNanSINR(firstNanIdx:end));

                fprintf(['\n[FigureHelper:plotTargetUTThroughput] 경고 — ' ...
                    'Target UT SINR_dB 원본 데이터 중 %.2f%%가 NaN입니다.\n'], nanRatio);
                fprintf('  최초 NaN 발생 슬롯      : %d (slotIndex 기준)\n', slots(firstNanIdx));
                if ~isempty(attackStartIdx)
                    fprintf('  Attack Start 슬롯       : %d\n', slots(attackStartIdx));
                    fprintf('  최초 NaN - Attack Start : %+d 슬롯\n', slots(firstNanIdx) - slots(attackStartIdx));
                end
                if isPermanentlyBroken
                    fprintf(['  -> 최초 NaN 발생 이후 끝까지 단 한 번도 회복되지 않음.\n' ...
                        '     확률적/간헐적 오류가 아니라, 특정 조건(예: 재밍 채널 충돌)에서\n' ...
                        '     항상 NaN을 반환하는 구조적 버그일 가능성이 높습니다.\n']);
                else
                    fprintf('  마지막 유효 SINR 슬롯   : %d (그 이후에도 간헐적으로 유효값 존재)\n', slots(lastValidIdx));
                end
                fprintf(['  -> UT.m의 SINR 계산 함수(performHARQ 내부 calculateSINR 등)를\n' ...
                    '     확인해서 이 슬롯 부근에서 어떤 조건이 NaN을 만드는지 점검 필요.\n\n']);
            end

        end
    
    
    end
end