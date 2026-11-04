%% ==================== final6_plot.m ====================
% final6_results.mat을 로드해서 그래프만 다시 그리는 스크립트.
% 시뮬레이션 재실행 없이, 색상/스타일/레이아웃만 자유롭게 수정 가능.
%
% (a)(b)(c) 세 그림을 하나의 x축(APJ-Target Distance) 위에
% 좌측 y축(Rate, %) + 우측 y축(SINR, dB) 이중축으로 통합.

clc; clear; close all;

load('final6_results.mat');


%% ================================================================
%  Combined Figure: JHR / ACK (left, %) + SINR (right, dB) vs Distance
% ================================================================

fig = figure('Color', 'w', 'Position', [100 100 750 480]);

colorJHR = [0 0.45 0.74];     % blue
colorACK = [0.85 0.33 0.10];  % orange
colorSINR = [0.55 0.35 0.75]; % purple

yyaxis left
hold on;
hJHR = errorbar(distanceList_km, meanHit, ciHit, '-o', ...
    'LineWidth', 1.5, 'MarkerSize', 6, 'CapSize', 7, 'Color', colorJHR);
hACK = errorbar(distanceList_km, meanAck, ciAck, '-s', ...
    'LineWidth', 1.5, 'MarkerSize', 6, 'CapSize', 7, 'Color', colorACK);
yline(baselineMeanACK, '--', sprintf('No Attack: %.1f%%', baselineMeanACK), ...
    'LineWidth', 1.2, 'Color', [0.4 0.4 0.4], ...
    'LabelHorizontalAlignment', 'right', 'LabelVerticalAlignment', 'bottom', ...
    'HandleVisibility', 'off');
ylabel('Rate (%)', 'FontSize', 11);
ylim([0 100]);
set(gca, 'YColor', 'k');
hold off;

yyaxis right
hSINR = errorbar(distanceList_km, meanSinr, ciSinr, '-^', ...
    'LineWidth', 1.5, 'MarkerSize', 6, 'CapSize', 7, 'Color', colorSINR);
ylabel('Target UT SINR (dB)', 'FontSize', 11);
set(gca, 'YColor', colorSINR);

set(gca, 'XScale', 'log');
xticks(distanceList_km);
xticklabels(arrayfun(@(d) sprintf('%g', d), distanceList_km, 'UniformOutput', false));
xlabel('APJ-Target Distance (km)', 'FontSize', 11);
xlim([min(distanceList_km)*0.7, max(distanceList_km)*1.4]);

title(sprintf('Attack Performance vs APJ-Target Distance (n=%d)', numTrials), ...
    'FontWeight', 'normal');
legend([hJHR, hACK, hSINR], ...
    {'Jamming Hit Rate', 'Target ACK Success Rate', 'Target UT SINR'}, ...
    'Location', 'best');

grid on; box on;
set(gca, 'FontSize', 10, 'LineWidth', 1, 'XMinorGrid', 'off');

exportgraphics(fig, 'final6_fig_distance_sweep_combined.pdf', 'ContentType', 'vector');
exportgraphics(fig, 'final6_fig_distance_sweep_combined.png', 'Resolution', 300);


%% ================================================================
%  콘솔 요약
% ================================================================

fprintf("\n============================================================\n");
fprintf(" APJ-Target Distance Sweep — Loaded Results Summary\n");
fprintf("============================================================\n");
fprintf("%-14s : ACK %.2f%% ± %.2f (95%% CI)\n", "No-Attack", baselineMeanACK, baselineCiACK);
for i = 1:numDistances
    fprintf("Distance=%6.2fkm : JHR %.2f%% ± %.2f | ACK %.2f%% ± %.2f | SINR %.3f dB ± %.3f\n", ...
        distanceList_km(i), meanHit(i), ciHit(i), meanAck(i), ciAck(i), meanSinr(i), ciSinr(i));
end
fprintf("============================================================\n");

fprintf("\n그래프 저장 완료:\n");
fprintf("  final6_fig_distance_sweep_combined.png/pdf\n");