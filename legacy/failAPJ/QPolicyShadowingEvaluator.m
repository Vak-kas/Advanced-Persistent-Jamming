classdef QPolicyShadowingEvaluator < handle

    properties

        %% ============================================================
        % Basic History
        %% ============================================================

        SlotHistory

        BeamGreedyHistory
        APJGreedyHistory

        GreedyMatchHistory


        %% ============================================================
        % Q-Vector Similarity
        %% ============================================================

        QMAEHistory
        QRMSEHistory
        QMaxErrorHistory

        CosineHistory
        PearsonHistory


        %% ============================================================
        % Decision Margin
        %% ============================================================

        BeamMarginHistory
        APJMarginHistory


        %% ============================================================
        % Analysis Parameters
        %% ============================================================

        RecentWindow = 100

    end



    methods

        %% ============================================================
        % Constructor
        %% ============================================================
        function obj = QPolicyShadowingEvaluator()

            obj.reset();

        end



        %% ============================================================
        % Reset
        %% ============================================================
        function reset(obj)

            obj.SlotHistory = [];

            obj.BeamGreedyHistory = [];
            obj.APJGreedyHistory = [];

            obj.GreedyMatchHistory = [];

            obj.QMAEHistory = [];
            obj.QRMSEHistory = [];
            obj.QMaxErrorHistory = [];

            obj.CosineHistory = [];
            obj.PearsonHistory = [];

            obj.BeamMarginHistory = [];
            obj.APJMarginHistory = [];

        end



        %% ============================================================
        % Record Q-Policy Comparison
        %
        % 동일한 State에 대해
        %
        % Beam1 Q-vector
        % APJ Q-vector
        %
        % 를 받아 분석 및 저장
        %% ============================================================
        function record(obj, slotIndex, beamQValues, apjQValues)

            %% --------------------------------------------------------
            % Vector 정리
            %% --------------------------------------------------------

            beamQ = double(beamQValues(:));
            apjQ  = double(apjQValues(:));


            if numel(beamQ) ~= numel(apjQ)

                error( ...
                    'Beam Q-vector and APJ Q-vector must have same size.' ...
                );

            end


            numActions = numel(beamQ);


            %% --------------------------------------------------------
            % Q Difference
            %% --------------------------------------------------------

            qDifference = ...
                beamQ - apjQ;


            qMAE = ...
                mean(abs(qDifference));


            qRMSE = ...
                sqrt(mean(qDifference.^2));


            qMaxError = ...
                max(abs(qDifference));


            %% --------------------------------------------------------
            % Cosine Similarity
            %% --------------------------------------------------------

            denominator = ...
                norm(beamQ) * norm(apjQ);


            if denominator > 0

                cosineSimilarity = ...
                    dot(beamQ, apjQ) / denominator;

            else

                cosineSimilarity = NaN;

            end


            %% --------------------------------------------------------
            % Pearson Correlation
            %% --------------------------------------------------------

            if std(beamQ) > 0 && ...
               std(apjQ) > 0

                correlationMatrix = ...
                    corrcoef(beamQ, apjQ);

                pearsonCorrelation = ...
                    correlationMatrix(1, 2);

            else

                pearsonCorrelation = NaN;

            end


            %% --------------------------------------------------------
            % Greedy Action
            %% --------------------------------------------------------

            [~, beamGreedy] = ...
                max(beamQ);

            [~, apjGreedy] = ...
                max(apjQ);


            greedyMatch = ...
                (beamGreedy == apjGreedy);


            %% --------------------------------------------------------
            % Beam Top-2 Margin
            %% --------------------------------------------------------

            sortedBeamQ = ...
                sort(beamQ, 'descend');


            if numActions >= 2

                beamMargin = ...
                    sortedBeamQ(1) - ...
                    sortedBeamQ(2);

            else

                beamMargin = NaN;

            end


            %% --------------------------------------------------------
            % APJ Top-2 Margin
            %% --------------------------------------------------------

            sortedAPJQ = ...
                sort(apjQ, 'descend');


            if numActions >= 2

                apjMargin = ...
                    sortedAPJQ(1) - ...
                    sortedAPJQ(2);

            else

                apjMargin = NaN;

            end


            %% --------------------------------------------------------
            % History 저장
            %% --------------------------------------------------------

            obj.SlotHistory(end + 1) = ...
                slotIndex;


            obj.BeamGreedyHistory(end + 1) = ...
                beamGreedy;


            obj.APJGreedyHistory(end + 1) = ...
                apjGreedy;


            obj.GreedyMatchHistory(end + 1) = ...
                greedyMatch;


            obj.QMAEHistory(end + 1) = ...
                qMAE;


            obj.QRMSEHistory(end + 1) = ...
                qRMSE;


            obj.QMaxErrorHistory(end + 1) = ...
                qMaxError;


            obj.CosineHistory(end + 1) = ...
                cosineSimilarity;


            obj.PearsonHistory(end + 1) = ...
                pearsonCorrelation;


            obj.BeamMarginHistory(end + 1) = ...
                beamMargin;


            obj.APJMarginHistory(end + 1) = ...
                apjMargin;

        end



        %% ============================================================
        % 현재 Slot 결과 출력
        %% ============================================================
        function printCurrent(obj)

            if isempty(obj.SlotHistory)
                return;
            end


            index = ...
                numel(obj.SlotHistory);


            slotIndex = ...
                obj.SlotHistory(index);


            beamGreedy = ...
                obj.BeamGreedyHistory(index);


            apjGreedy = ...
                obj.APJGreedyHistory(index);


            isMatch = ...
                obj.GreedyMatchHistory(index);


            %% --------------------------------------------------------
            % 누적 Agreement
            %% --------------------------------------------------------

            overallAgreement = ...
                mean(obj.GreedyMatchHistory) * 100;


            recentWindow = ...
                min( ...
                    obj.RecentWindow, ...
                    numel(obj.GreedyMatchHistory) ...
                );


            recentAgreement = ...
                mean( ...
                    obj.GreedyMatchHistory( ...
                        end-recentWindow+1:end ...
                    ) ...
                ) * 100;


            %% --------------------------------------------------------
            % 출력
            %% --------------------------------------------------------

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


            if isMatch

                fprintf('  Result                   : MATCH\n');

            else

                fprintf('  Result                   : MISMATCH\n');

            end


            fprintf('\n');

            fprintf('  [Cumulative]\n');

            fprintf('    Samples                : %d\n', ...
                numel(obj.GreedyMatchHistory));

            fprintf('    Greedy Agreement       : %.2f %%\n', ...
                overallAgreement);

            fprintf('    Recent Agreement (%3d): %.2f %%\n', ...
                recentWindow, ...
                recentAgreement);

            fprintf('============================================================\n');

        end



        %% ============================================================
        % 최종 Q-Policy Shadowing Summary
        %% ============================================================
        function printSummary(obj)

            if isempty(obj.SlotHistory)

                fprintf('\n');
                fprintf('============================================================\n');
                fprintf('BEAM1 - APJ Q-POLICY SHADOWING SUMMARY\n');
                fprintf('============================================================\n');
                fprintf('  No samples recorded.\n');
                fprintf('============================================================\n');

                return;

            end


            %% --------------------------------------------------------
            % Basic
            %% --------------------------------------------------------

            totalSamples = ...
                numel(obj.SlotHistory);


            totalMatch = ...
                sum(obj.GreedyMatchHistory);


            totalMismatch = ...
                totalSamples - totalMatch;


            overallAgreement = ...
                mean(obj.GreedyMatchHistory) * 100;


            %% --------------------------------------------------------
            % Recent
            %% --------------------------------------------------------

            recentWindow = ...
                min(obj.RecentWindow, totalSamples);


            recentIndices = ...
                totalSamples-recentWindow+1 : totalSamples;


            recentAgreement = ...
                mean( ...
                    obj.GreedyMatchHistory(recentIndices) ...
                ) * 100;


            %% --------------------------------------------------------
            % Overall Q Similarity
            %% --------------------------------------------------------

            averageQMAE = ...
                mean(obj.QMAEHistory, 'omitnan');


            averageQRMSE = ...
                mean(obj.QRMSEHistory, 'omitnan');


            averageCosine = ...
                mean(obj.CosineHistory, 'omitnan');


            averagePearson = ...
                mean(obj.PearsonHistory, 'omitnan');


            %% --------------------------------------------------------
            % Recent Q Similarity
            %% --------------------------------------------------------

            recentQMAE = ...
                mean( ...
                    obj.QMAEHistory(recentIndices), ...
                    'omitnan' ...
                );


            recentQRMSE = ...
                mean( ...
                    obj.QRMSEHistory(recentIndices), ...
                    'omitnan' ...
                );


            recentCosine = ...
                mean( ...
                    obj.CosineHistory(recentIndices), ...
                    'omitnan' ...
                );


            recentPearson = ...
                mean( ...
                    obj.PearsonHistory(recentIndices), ...
                    'omitnan' ...
                );


            %% --------------------------------------------------------
            % Margin
            %% --------------------------------------------------------

            averageBeamMargin = ...
                mean(obj.BeamMarginHistory, 'omitnan');


            averageAPJMargin = ...
                mean(obj.APJMarginHistory, 'omitnan');


            %% --------------------------------------------------------
            % 출력
            %% --------------------------------------------------------

            fprintf('\n');
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('BEAM1 - APJ Q-POLICY SHADOWING SUMMARY\n');
            fprintf('============================================================\n');

            fprintf('  Number of Samples        : %d\n', ...
                totalSamples);

            fprintf('  First Slot               : %d\n', ...
                obj.SlotHistory(1));

            fprintf('  Last Slot                : %d\n', ...
                obj.SlotHistory(end));


            fprintf('\n');
            fprintf('  [Greedy Policy Agreement]\n');

            fprintf('    Matched                : %d\n', ...
                totalMatch);

            fprintf('    Mismatched             : %d\n', ...
                totalMismatch);

            fprintf('    Overall Agreement      : %.2f %%\n', ...
                overallAgreement);

            fprintf('    Recent Agreement (%3d): %.2f %%\n', ...
                recentWindow, ...
                recentAgreement);


            fprintf('\n');
            fprintf('  [Q-Vector Similarity - Overall]\n');

            fprintf('    Average Q-MAE          : %.6f\n', ...
                averageQMAE);

            fprintf('    Average Q-RMSE         : %.6f\n', ...
                averageQRMSE);

            fprintf('    Average Cosine         : %.6f\n', ...
                averageCosine);

            fprintf('    Average Pearson Corr.  : %.6f\n', ...
                averagePearson);


            fprintf('\n');
            fprintf('  [Q-Vector Similarity - Recent %d]\n', ...
                recentWindow);

            fprintf('    Average Q-MAE          : %.6f\n', ...
                recentQMAE);

            fprintf('    Average Q-RMSE         : %.6f\n', ...
                recentQRMSE);

            fprintf('    Average Cosine         : %.6f\n', ...
                recentCosine);

            fprintf('    Average Pearson Corr.  : %.6f\n', ...
                recentPearson);


            fprintf('\n');
            fprintf('  [Decision Margin]\n');

            fprintf('    Avg Beam1 Top-2 Margin : %.6f\n', ...
                averageBeamMargin);

            fprintf('    Avg APJ Top-2 Margin   : %.6f\n', ...
                averageAPJMargin);


            fprintf('============================================================\n');

        end



        %% ============================================================
        % ★ 최종 Margin 분석
        %
        % MATCH일 때 Beam margin
        % MISMATCH일 때 Beam margin
        %
        % 비교
        %% ============================================================
        function printMarginAnalysisSummary(obj)

            fprintf('\n');
            fprintf('\n');
            fprintf('============================================================\n');
            fprintf('GREEDY MATCH / MISMATCH MARGIN ANALYSIS\n');
            fprintf('============================================================\n');


            if isempty(obj.BeamMarginHistory)

                fprintf('  No margin samples recorded.\n');
                fprintf('============================================================\n');

                return;

            end


            margins = ...
                obj.BeamMarginHistory(:);


            matches = ...
                logical(obj.GreedyMatchHistory(:));


            %% --------------------------------------------------------
            % NaN 제거
            %% --------------------------------------------------------

            validMask = ...
                ~isnan(margins);


            margins = ...
                margins(validMask);


            matches = ...
                matches(validMask);


            %% --------------------------------------------------------
            % MATCH / MISMATCH
            %% --------------------------------------------------------

            matchMargins = ...
                margins(matches);


            mismatchMargins = ...
                margins(~matches);


            totalSamples = ...
                numel(margins);


            numMatch = ...
                numel(matchMargins);


            numMismatch = ...
                numel(mismatchMargins);


            %% --------------------------------------------------------
            % 전체 통계
            %% --------------------------------------------------------

            if ~isempty(matchMargins)

                avgMatchMargin = ...
                    mean(matchMargins);

                medianMatchMargin = ...
                    median(matchMargins);

                stdMatchMargin = ...
                    std(matchMargins);

            else

                avgMatchMargin = NaN;
                medianMatchMargin = NaN;
                stdMatchMargin = NaN;

            end


            if ~isempty(mismatchMargins)

                avgMismatchMargin = ...
                    mean(mismatchMargins);

                medianMismatchMargin = ...
                    median(mismatchMargins);

                stdMismatchMargin = ...
                    std(mismatchMargins);

            else

                avgMismatchMargin = NaN;
                medianMismatchMargin = NaN;
                stdMismatchMargin = NaN;

            end


            %% --------------------------------------------------------
            % Ratio
            %% --------------------------------------------------------

            if ~isnan(avgMismatchMargin) && ...
               avgMismatchMargin > 0

                marginRatio = ...
                    avgMatchMargin / avgMismatchMargin;

            else

                marginRatio = NaN;

            end


            %% --------------------------------------------------------
            % Recent Window
            %% --------------------------------------------------------

            recentWindow = ...
                min(obj.RecentWindow, numel(margins));


            recentIndices = ...
                numel(margins)-recentWindow+1 : ...
                numel(margins);


            recentMargins = ...
                margins(recentIndices);


            recentMatches = ...
                matches(recentIndices);


            recentMatchMargins = ...
                recentMargins(recentMatches);


            recentMismatchMargins = ...
                recentMargins(~recentMatches);


            if ~isempty(recentMatchMargins)

                recentAvgMatchMargin = ...
                    mean(recentMatchMargins);

            else

                recentAvgMatchMargin = NaN;

            end


            if ~isempty(recentMismatchMargins)

                recentAvgMismatchMargin = ...
                    mean(recentMismatchMargins);

            else

                recentAvgMismatchMargin = NaN;

            end


            if ~isnan(recentAvgMismatchMargin) && ...
               recentAvgMismatchMargin > 0

                recentMarginRatio = ...
                    recentAvgMatchMargin / ...
                    recentAvgMismatchMargin;

            else

                recentMarginRatio = NaN;

            end


            %% --------------------------------------------------------
            % 출력
            %% --------------------------------------------------------

            fprintf('  Number of Samples        : %d\n', ...
                totalSamples);


            fprintf('\n');
            fprintf('  [Greedy MATCH]\n');

            fprintf('    Samples                : %d\n', ...
                numMatch);

            fprintf('    Average Beam Margin    : %.6f\n', ...
                avgMatchMargin);

            fprintf('    Median Beam Margin     : %.6f\n', ...
                medianMatchMargin);

            fprintf('    Std. Beam Margin       : %.6f\n', ...
                stdMatchMargin);


            fprintf('\n');
            fprintf('  [Greedy MISMATCH]\n');

            fprintf('    Samples                : %d\n', ...
                numMismatch);

            fprintf('    Average Beam Margin    : %.6f\n', ...
                avgMismatchMargin);

            fprintf('    Median Beam Margin     : %.6f\n', ...
                medianMismatchMargin);

            fprintf('    Std. Beam Margin       : %.6f\n', ...
                stdMismatchMargin);


            fprintf('\n');
            fprintf('  [Overall Comparison]\n');

            fprintf('    MATCH / MISMATCH Ratio : %.3f x\n', ...
                marginRatio);

            fprintf('    Mean Margin Difference : %.6f\n', ...
                avgMatchMargin - ...
                avgMismatchMargin);


            fprintf('\n');
            fprintf('  [Recent %d Samples]\n', ...
                recentWindow);

            fprintf('    MATCH Samples          : %d\n', ...
                numel(recentMatchMargins));

            fprintf('    MISMATCH Samples       : %d\n', ...
                numel(recentMismatchMargins));

            fprintf('    MATCH Avg Margin       : %.6f\n', ...
                recentAvgMatchMargin);

            fprintf('    MISMATCH Avg Margin    : %.6f\n', ...
                recentAvgMismatchMargin);

            fprintf('    MATCH / MISMATCH Ratio : %.3f x\n', ...
                recentMarginRatio);


            fprintf('\n');
            fprintf('  [Interpretation]\n');


            if avgMatchMargin > avgMismatchMargin

                fprintf( ...
                    '    MATCH states have larger Beam1 Top-2 margins.\n' ...
                );

                fprintf( ...
                    '    MISMATCH tends to occur closer to greedy decision boundaries.\n' ...
                );

            else

                fprintf( ...
                    '    Smaller Beam1 margin is not associated with MISMATCH in this run.\n' ...
                );

            end


            fprintf('============================================================\n');

        end



        %% ============================================================
        % Plot All
        %% ============================================================
        function plotAll(obj)

            if isempty(obj.SlotHistory)
                return;
            end


            obj.plotGreedyAgreement();

            obj.plotQMAE();

            obj.plotCosineSimilarity();

            obj.plotPearsonCorrelation();

            obj.plotMarginBoxchart();

            obj.plotAgreementVsMargin();

        end



        %% ============================================================
        % Greedy Agreement Moving Average
        %% ============================================================
        function plotGreedyAgreement(obj)

            matchHistory = ...
                double(obj.GreedyMatchHistory);


            movingAgreement = ...
                movmean( ...
                    matchHistory, ...
                    [obj.RecentWindow-1 0] ...
                );


            figure;

            plot( ...
                obj.SlotHistory, ...
                movingAgreement * 100, ...
                'LineWidth', ...
                1.5 ...
            );


            xlabel('Time Slot');

            ylabel('Greedy Agreement (%)');

            title( ...
                sprintf( ...
                    'Beam1-APJ Greedy Policy Agreement (Window = %d)', ...
                    obj.RecentWindow ...
                ) ...
            );

            ylim([0 100]);

            grid on;

        end



        %% ============================================================
        % Q-MAE Moving Average
        %% ============================================================
        function plotQMAE(obj)

            movingQMAE = ...
                movmean( ...
                    obj.QMAEHistory, ...
                    [obj.RecentWindow-1 0] ...
                );


            figure;

            plot( ...
                obj.SlotHistory, ...
                movingQMAE, ...
                'LineWidth', ...
                1.5 ...
            );


            xlabel('Time Slot');

            ylabel('Q-Value MAE');

            title( ...
                sprintf( ...
                    'Beam1-APJ Q-Value MAE (Window = %d)', ...
                    obj.RecentWindow ...
                ) ...
            );

            grid on;

        end



        %% ============================================================
        % Cosine Similarity
        %% ============================================================
        function plotCosineSimilarity(obj)

            movingCosine = ...
                movmean( ...
                    obj.CosineHistory, ...
                    [obj.RecentWindow-1 0], ...
                    'omitnan' ...
                );


            figure;

            plot( ...
                obj.SlotHistory, ...
                movingCosine, ...
                'LineWidth', ...
                1.5 ...
            );


            xlabel('Time Slot');

            ylabel('Cosine Similarity');

            title( ...
                sprintf( ...
                    'Beam1-APJ Q-Vector Cosine Similarity (Window = %d)', ...
                    obj.RecentWindow ...
                ) ...
            );

            ylim([0 1]);

            grid on;

        end



        %% ============================================================
        % Pearson Correlation
        %% ============================================================
        function plotPearsonCorrelation(obj)

            movingPearson = ...
                movmean( ...
                    obj.PearsonHistory, ...
                    [obj.RecentWindow-1 0], ...
                    'omitnan' ...
                );


            figure;

            plot( ...
                obj.SlotHistory, ...
                movingPearson, ...
                'LineWidth', ...
                1.5 ...
            );


            xlabel('Time Slot');

            ylabel('Pearson Correlation');

            title( ...
                sprintf( ...
                    'Beam1-APJ Q-Vector Pearson Correlation (Window = %d)', ...
                    obj.RecentWindow ...
                ) ...
            );

            ylim([-1 1]);

            grid on;

        end



        %% ============================================================
        % MATCH vs MISMATCH Margin Boxchart
        %% ============================================================
        function plotMarginBoxchart(obj)

            margins = ...
                obj.BeamMarginHistory(:);


            matches = ...
                logical(obj.GreedyMatchHistory(:));


            validMask = ...
                ~isnan(margins);


            margins = ...
                margins(validMask);


            matches = ...
                matches(validMask);


            matchMargins = ...
                margins(matches);


            mismatchMargins = ...
                margins(~matches);


            group = [
                ones(size(matchMargins));
                2 * ones(size(mismatchMargins))
            ];


            values = [
                matchMargins;
                mismatchMargins
            ];


            figure;

            boxchart( ...
                group, ...
                values ...
            );


            xticks([1 2]);

            xticklabels( ...
                {'MATCH', 'MISMATCH'} ...
            );


            ylabel( ...
                'Beam1 Top-2 Q-Value Margin' ...
            );


            title( ...
                'Beam1 Decision Margin: Greedy Match vs Mismatch' ...
            );


            grid on;

        end



        %% ============================================================
        % Margin vs Greedy Agreement
        %% ============================================================
        function plotAgreementVsMargin(obj)

            margins = ...
                obj.BeamMarginHistory(:);


            matches = ...
                double(obj.GreedyMatchHistory(:));


            validMask = ...
                ~isnan(margins);


            margins = ...
                margins(validMask);


            matches = ...
                matches(validMask);


            if isempty(margins)
                return;
            end


            %% --------------------------------------------------------
            % Bin
            %% --------------------------------------------------------

            numBins = 10;


            minMargin = ...
                min(margins);


            maxMargin = ...
                max(margins);


            if maxMargin == minMargin
                return;
            end


            binEdges = ...
                linspace( ...
                    minMargin, ...
                    maxMargin, ...
                    numBins + 1 ...
                );


            binCenters = ...
                zeros(1, numBins);


            agreementRate = ...
                nan(1, numBins);


            for binIndex = 1:numBins

                if binIndex < numBins

                    mask = ...
                        margins >= binEdges(binIndex) & ...
                        margins < binEdges(binIndex + 1);

                else

                    mask = ...
                        margins >= binEdges(binIndex) & ...
                        margins <= binEdges(binIndex + 1);

                end


                binCenters(binIndex) = ...
                    ( ...
                        binEdges(binIndex) + ...
                        binEdges(binIndex + 1) ...
                    ) / 2;


                if any(mask)

                    agreementRate(binIndex) = ...
                        mean(matches(mask)) * 100;

                end

            end


            %% --------------------------------------------------------
            % Plot
            %% --------------------------------------------------------

            figure;

            plot( ...
                binCenters, ...
                agreementRate, ...
                '-o', ...
                'LineWidth', ...
                1.5 ...
            );


            xlabel( ...
                'Beam1 Top-2 Q-Value Margin' ...
            );


            ylabel( ...
                'Greedy Agreement (%)' ...
            );


            title( ...
                'Greedy Agreement vs Beam1 Decision Margin' ...
            );


            ylim([0 100]);

            grid on;

        end

    end
end