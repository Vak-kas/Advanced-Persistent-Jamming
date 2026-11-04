classdef FigureHelper
    methods (Static)

        function ax = plotUTDeployment(UTs, groundWidth, groundHeight)

            figure;
            ax = axes;

            hold(ax, 'on');
            grid(ax, 'on');
            box(ax, 'on');

            xlim(ax, [0 groundWidth] / 1e3);
            ylim(ax, [0 groundHeight] / 1e3);

            xlabel(ax, 'X (km)');
            ylabel(ax, 'Y (km)');
            title(ax, 'UT and APJ Deployment');

            for n = 1:numel(UTs)

                x = UTs(n).Position(1) / 1e3;
                y = UTs(n).Position(2) / 1e3;

                if UTs(n).IsTarget
                    scatter(ax, x, y, 80, 'r', 'filled');
                else
                    scatter(ax, x, y, 80, 'b', 'filled');
                end

                text(ax, x, y, sprintf('%d', UTs(n).Id), ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', ...
                    'Color', 'w', ...
                    'FontWeight', 'bold');
            end

            axis(ax, 'equal');
        end


        function plotAPJ(ax, APJ)

            x = APJ.Position(1) / 1e3;
            y = APJ.Position(2) / 1e3;

            scatter(ax, x, y, ...
                180, ...
                'p', ...
                'MarkerFaceColor', 'k', ...
                'MarkerEdgeColor', 'k');

            text(ax, x, y + 1, ...
                sprintf('APJ %d', APJ.Id), ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'bottom', ...
                'FontWeight', 'bold', ...
                'Color', 'k');
        end

    end
end