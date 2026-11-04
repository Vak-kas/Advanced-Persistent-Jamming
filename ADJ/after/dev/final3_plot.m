%% ==================== final3_plot.m ====================
% final3_results.mat을 로드해서 그래프만 다시 그리는 스크립트.
% 시뮬레이션 재실행 없이, 색상/스타일/레이아웃만 자유롭게 수정 가능.

clc; clear; close all;

load('final3_results.mat');

lineColors = [0.30 0.55 0.75;   % Random - 회청
              0.85 0.55 0.20;   % Sweep - 주황
              0.55 0.35 0.75;   % Comb - 보라
              0.20 0.60 0.35];  % APJ - 초록

%% ================================================================
%  Fig. 1(a)
%  Time-varying Jamming Hit Rate  [MAIN RESULT]
% ================================================================

fig1 = figure('Color', 'w', 'Position', [100 100 900 480]);
hold on;

lineHandles = gobjects(numTechniques, 1);

for techniqueIndex = 1:numTechniques

    y = meanHitTime(techniqueIndex, :);
    ci = ciHitTime(techniqueIndex, :);

    valid = ~isnan(y);

    if ~any(valid)
        continue;
    end

    xValid  = slots(valid);
    yValid  = y(valid);
    ciValid = ci(valid);

    xPatch = [xValid, fliplr(xValid)];
    yPatch = [yValid - ciValid, fliplr(yValid + ciValid)];

    patch(xPatch, yPatch, lineColors(techniqueIndex,:), ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');

    lineHandles(techniqueIndex) = plot(xValid, yValid, ...
        'LineWidth', 2.0, 'Color', lineColors(techniqueIndex,:));

end


xline(reconDurationUsed + 1, '--', 'Attack Start', ...
    'LineWidth', 1.3, 'Color', [0.4 0.4 0.4], ...
    'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');

% No-Attack에는 Jamming Hit Rate 개념이 없으므로 (a)에는 기준선 없음

xlabel("Time Slot", 'FontSize', 11);
ylabel("Jamming Hit Rate (%)", 'FontSize', 11);

title(sprintf("(a) Jamming Hit Rate over Time (%d-slot Moving Average)", movingWindow), ...
    'FontWeight', 'normal');

legend(lineHandles, techniqueNames, 'Location', 'best');

ylim([0 100]);
xlim([1 totalSlots]);

grid on; box on;
set(gca, 'FontSize', 10, 'LineWidth', 1.0);

hold off;

exportgraphics(fig1, 'final3_fig1a_jamming_hit_rate.pdf', 'ContentType', 'vector');
exportgraphics(fig1, 'final3_fig1a_jamming_hit_rate.png', 'Resolution', 300);


%% ================================================================
%  Fig. 1(b)
%  Time-varying Target ACK Success Rate  [MAIN RESULT]
%  + No-Attack baseline shaded band 포함
% ================================================================

fig2 = figure('Color', 'w', 'Position', [100 100 900 480]);
hold on;

lineHandles = gobjects(numTechniques, 1);

% ---- No-Attack baseline (반투명 회색 band + 점선 평균선) ----
yBase  = meanBaselineACKTime;
ciBase = ciBaselineACKTime;
validBase = ~isnan(yBase);

if any(validBase)
    xValidBase  = slots(validBase);
    yValidBase  = yBase(validBase);
    ciValidBase = ciBase(validBase);

    xPatchBase = [xValidBase, fliplr(xValidBase)];
    yPatchBase = [yValidBase - ciValidBase, fliplr(yValidBase + ciValidBase)];

    patch(xPatchBase, yPatchBase, [0.5 0.5 0.5], ...
        'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');

    baselineHandle = plot(xValidBase, yValidBase, '--', ...
        'LineWidth', 1.6, 'Color', [0.4 0.4 0.4]);
else
    baselineHandle = gobjects(1);
end


for techniqueIndex = 1:numTechniques

    y = meanACKTime(techniqueIndex, :);
    ci = ciACKTime(techniqueIndex, :);

    valid = ~isnan(y);

    if ~any(valid)
        continue;
    end

    xValid  = slots(valid);
    yValid  = y(valid);
    ciValid = ci(valid);

    xPatch = [xValid, fliplr(xValid)];
    yPatch = [yValid - ciValid, fliplr(yValid + ciValid)];

    patch(xPatch, yPatch, lineColors(techniqueIndex,:), ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');

    lineHandles(techniqueIndex) = plot(xValid, yValid, ...
        'LineWidth', 2.0, 'Color', lineColors(techniqueIndex,:));

end


xline(reconDurationUsed + 1, '--', 'Attack Start', ...
    'LineWidth', 1.3, 'Color', [0.4 0.4 0.4], ...
    'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');


xlabel("Time Slot", 'FontSize', 11);
ylabel("Target ACK Success Rate (%)", 'FontSize', 11);

title(sprintf("(b) Target ACK Success Rate over Time (%d-slot Moving Average)", movingWindow), ...
    'FontWeight', 'normal');

allHandles = [lineHandles; baselineHandle];
allLabels  = [techniqueNames; "No-Attack"];
validHandleIdx = arrayfun(@(h) isgraphics(h), allHandles);

legend(allHandles(validHandleIdx), allLabels(validHandleIdx), 'Location', 'best');

ylim([0 100]);
xlim([1 totalSlots]);

grid on; box on;
set(gca, 'FontSize', 10, 'LineWidth', 1.0);

hold off;

exportgraphics(fig2, 'final3_fig1b_ack_success_rate.pdf', 'ContentType', 'vector');
exportgraphics(fig2, 'final3_fig1b_ack_success_rate.png', 'Resolution', 300);


%% ================================================================
%  Fig. 1(c)
%  Overall Attack-Phase Performance  [SECONDARY RESULT]
%  + No-Attack ACK baseline을 yline으로 표시
% ================================================================

fig3 = figure('Color', 'w', 'Position', [100 100 800 480]);
hold on;

x = 1:numTechniques;
offset = 0.10;

h1 = errorbar(x - offset, meanHit, ciHit, 'o', ...
    'LineStyle', 'none', 'LineWidth', 1.6, 'MarkerSize', 8, ...
    'CapSize', 10, 'Color', [0.20 0.40 0.70], 'MarkerFaceColor', [0.20 0.40 0.70]);

h2 = errorbar(x + offset, meanSuc, ciSuc, 's', ...
    'LineStyle', 'none', 'LineWidth', 1.6, 'MarkerSize', 8, ...
    'CapSize', 10, 'Color', [0.80 0.30 0.20], 'MarkerFaceColor', [0.80 0.30 0.20]);

yline(baselineMeanACK, '--', sprintf('No-Attack ACK: %.1f%%', baselineMeanACK), ...
    'LineWidth', 1.3, 'Color', [0.4 0.4 0.4], ...
    'LabelHorizontalAlignment', 'right', 'LabelVerticalAlignment', 'bottom', ...
    'HandleVisibility', 'off');


xticks(x);
xticklabels(techniqueNames);

ylabel("Rate (%)", 'FontSize', 11);

title("(c) Overall Attack-Phase Performance", 'FontWeight', 'normal');

legend([h1 h2], ["Jamming Hit Rate", "Target ACK Success Rate"], 'Location', 'best');

ylim([0 100]);
xlim([0.5 numTechniques + 0.5]);

grid on; box on;
set(gca, 'FontSize', 10, 'LineWidth', 1.0);

hold off;

exportgraphics(fig3, 'final3_fig1c_overall_performance.pdf', 'ContentType', 'vector');
exportgraphics(fig3, 'final3_fig1c_overall_performance.png', 'Resolution', 300);


fprintf("\n============================================================\n");
fprintf(" Attack Method Comparison — Loaded Results Summary\n");
fprintf("============================================================\n");
fprintf("%-18s : ACK %.2f%% ± %.2f (95%% CI)\n", "No-Attack", baselineMeanACK, baselineCiACK);
for i = 1:numTechniques
    fprintf("%-18s : JHR %.2f%% ± %.2f | ACK %.2f%% ± %.2f | SINR %.3f dB ± %.3f\n", ...
        techniqueNames(i), meanHit(i), ciHit(i), meanSuc(i), ciSuc(i), meanSinr(i), ciSinr(i));
end
fprintf("============================================================\n");

fprintf("\n그래프 3개 저장 완료:\n");
fprintf("  final3_fig1a_jamming_hit_rate.png/pdf\n");
fprintf("  final3_fig1b_ack_success_rate.png/pdf\n");
fprintf("  final3_fig1c_overall_performance.png/pdf\n");