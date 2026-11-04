%% ==================== final11_plot.m ====================
% final11_results.mat을 로드해서 그래프만 다시 그리는 스크립트.
%
% Output:
%   (a) Jamming Hit Rate over Time          (mean + 95% CI shading)
%   (b) Target ACK Success Rate over Time   (mean + 95% CI shading)
%   (c) Overall Attack-Phase Performance    (mean + standard deviation)
%
% Fig. (c):
%   - Left  : Jamming Hit Rate
%   - Right : Target ACK Success Rate
%   - Error bars = Standard Deviation (아래쪽은 0%에서 clip)
%   - No-Attack ACK baseline은 ACK 그룹 구간에만 표시
%
% 시뮬레이션 재실행 불필요.

clc;
clear;
close all;

load('final11_results.mat');


%% ================================================================
%  Plot Configuration
% ================================================================

lineColors = [ ...
    0.30 0.55 0.75;   % Random
    0.85 0.55 0.20;   % Swept
    0.55 0.35 0.75;   % Comb
    0.80 0.20 0.20;   % DQN-IJ
    0.20 0.60 0.35];  % APJ

% 논문 본문 약칭과 통일한 표시용 이름
% (techniqueNames 순서가 Random, Sweep, Comb, DQN-IJ, APJ라고 가정)
displayNames = ["Random"; "Swept"; "Comb"; "DQN-IJ"; "APJ"];

% Attack starts after reconnaissance
attackStartSlot = reconDurationUsed + 1;

% 공격 구간 길이
numAttackSlots = totalSlots - attackStartSlot + 1;


%% ================================================================
%  Fig. (a)
%  Jamming Hit Rate over Time
% ================================================================

figA = figure('Color', 'w', 'Position', [100 100 720 480]);
hold on;

lineHandlesA = gobjects(numTechniques, 1);

for techniqueIndex = 1:numTechniques

    y  = meanHitTime(techniqueIndex, :);
    ci = ciHitTime(techniqueIndex, :);

    valid = ~isnan(y) & (slots >= attackStartSlot);

    if ~any(valid)
        continue;
    end

    xValid  = slots(valid) - attackStartSlot + 1;
    yValid  = y(valid);
    ciValid = ci(valid);

    % 95% CI shading (0~100% clip)
    lowerCI = max(0,   yValid - ciValid);
    upperCI = min(100, yValid + ciValid);

    patch([xValid, fliplr(xValid)], [lowerCI, fliplr(upperCI)], ...
        lineColors(techniqueIndex,:), ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');

    % Mean line
    lineHandlesA(techniqueIndex) = plot(xValid, yValid, ...
        'LineWidth', 2.0, 'Color', lineColors(techniqueIndex,:));

end

xlabel("Elapsed Attack Decision Epoch", 'FontSize', 11);
ylabel("Jamming Hit Rate (%)", 'FontSize', 11);

ylim([0 100]);
xlim([1 numAttackSlots]);

grid on;
box on;
set(gca, 'FontSize', 10, 'LineWidth', 1.0);

validHandlesA = arrayfun(@(h) isgraphics(h), lineHandlesA);
legend(lineHandlesA(validHandlesA), displayNames(validHandlesA), 'Location', 'best');

hold off;

exportgraphics(figA, 'final11_fig1a_jamming_hit_rate.pdf', 'ContentType', 'vector');
exportgraphics(figA, 'final11_fig1a_jamming_hit_rate.png', 'Resolution', 300);


%% ================================================================
%  Fig. (b)
%  Target ACK Success Rate over Time
% ================================================================

figB = figure('Color', 'w', 'Position', [100 100 720 480]);
hold on;

lineHandlesB = gobjects(numTechniques, 1);

% ----- No-Attack Baseline -----
yBase  = meanBaselineACKTime;
ciBase = ciBaselineACKTime;

validBase = ~isnan(yBase) & (slots >= attackStartSlot);

if any(validBase)

    xValidBase  = slots(validBase) - attackStartSlot + 1;
    yValidBase  = yBase(validBase);
    ciValidBase = ciBase(validBase);

    lowerBase = max(0,   yValidBase - ciValidBase);
    upperBase = min(100, yValidBase + ciValidBase);

    patch([xValidBase, fliplr(xValidBase)], [lowerBase, fliplr(upperBase)], ...
        [0.5 0.5 0.5], ...
        'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');

    baselineHandle = plot(xValidBase, yValidBase, '--', ...
        'LineWidth', 1.6, 'Color', [0.4 0.4 0.4]);

else
    baselineHandle = gobjects(1);
end

% ----- Attack Methods -----
for techniqueIndex = 1:numTechniques

    y  = meanACKTime(techniqueIndex, :);
    ci = ciACKTime(techniqueIndex, :);

    valid = ~isnan(y) & (slots >= attackStartSlot);

    if ~any(valid)
        continue;
    end

    xValid  = slots(valid) - attackStartSlot + 1;
    yValid  = y(valid);
    ciValid = ci(valid);

    lowerCI = max(0,   yValid - ciValid);
    upperCI = min(100, yValid + ciValid);

    patch([xValid, fliplr(xValid)], [lowerCI, fliplr(upperCI)], ...
        lineColors(techniqueIndex,:), ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');

    lineHandlesB(techniqueIndex) = plot(xValid, yValid, ...
        'LineWidth', 2.0, 'Color', lineColors(techniqueIndex,:));

end

xlabel("Elapsed Attack Decision Epoch", 'FontSize', 11);
ylabel("Target ACK Success Rate (%)", 'FontSize', 11);

ylim([0 100]);
xlim([1 numAttackSlots]);

grid on;
box on;
set(gca, 'FontSize', 10, 'LineWidth', 1.0);

allHandles = [lineHandlesB; baselineHandle];
allLabelsB = [displayNames; "No-Attack"];

validHandleIdx = arrayfun(@(h) isgraphics(h), allHandles);
legend(allHandles(validHandleIdx), allLabelsB(validHandleIdx), 'Location', 'best');

hold off;

exportgraphics(figB, 'final11_fig1b_ack_success_rate.pdf', 'ContentType', 'vector');
exportgraphics(figB, 'final11_fig1b_ack_success_rate.png', 'Resolution', 300);


%% ================================================================
%  Fig. (c)
%  Overall Attack-Phase Performance
%
%  Left  : Jamming Hit Rate
%  Right : Target ACK Success Rate
%  Error bar = Standard Deviation
% ================================================================

figC = figure('Color', 'w', 'Position', [100 100 900 680]);
hold on;

% ----- X positions -----
xHit     = 1:numTechniques;                            % JHR group
groupGap = 0.6;                                        % 그룹 간 간격
xACK     = (1:numTechniques) + numTechniques + groupGap;   % ACK group

% ----- Colors -----
colorHit = [0.20 0.40 0.70];
colorACK = [0.80 0.30 0.20];
barWidth = 0.65;

% ----- Bars -----
hHit = bar(xHit, meanHit, barWidth, 'FaceColor', colorHit, 'EdgeColor', 'none');
hACK = bar(xACK, meanSuc, barWidth, 'FaceColor', colorACK, 'EdgeColor', 'none');


%% ------------------------------------------------------------
% Standard-Deviation Error Bars
% 아래쪽은 0% 미만으로 내려가지 않게, 위쪽은 100% 초과하지 않게 clip
% ------------------------------------------------------------

lowerErrHit = min(stdHit, meanHit);
upperErrHit = min(stdHit, 100 - meanHit);

lowerErrACK = min(stdSuc, meanSuc);
upperErrACK = min(stdSuc, 100 - meanSuc);

errorbar(xHit, meanHit, lowerErrHit, upperErrHit, 'k', ...
    'LineStyle', 'none', 'LineWidth', 1.5, 'CapSize', 8, 'HandleVisibility', 'off');

errorbar(xACK, meanSuc, lowerErrACK, upperErrACK, 'k', ...
    'LineStyle', 'none', 'LineWidth', 1.5, 'CapSize', 8, 'HandleVisibility', 'off');


%% ------------------------------------------------------------
% No-Attack ACK Baseline (ACK 그룹 구간에만)
% ------------------------------------------------------------

xBaseStart = xACK(1) - 0.5;
xBaseEnd   = xACK(end) + 0.5;

plot([xBaseStart, xBaseEnd], [baselineMeanACK, baselineMeanACK], '--', ...
    'LineWidth', 1.3, 'Color', [0.55 0.55 0.55], 'HandleVisibility', 'off');

text(xBaseEnd, baselineMeanACK + 0.6, ...
    sprintf('No-Attack ACK (%.1f%%)', baselineMeanACK), ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
    'FontSize', 10, 'Color', [0.45 0.45 0.45]);


%% ------------------------------------------------------------
% Value Labels
% 기본: error bar 위
% 위쪽 공간이 없으면(No-Attack 선과 충돌): error bar 오른쪽 옆
% ------------------------------------------------------------

labelGap = 1.5;
sideOffset = 0.08;

% JHR labels
for i = 1:numTechniques

    labelY = meanHit(i) + upperErrHit(i) + labelGap;

    text(xHit(i), labelY, sprintf('%.1f', meanHit(i)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontSize', 9);

end

% ACK labels
for i = 1:numTechniques

    labelY = meanSuc(i) + upperErrACK(i) + labelGap;

    if labelY >= baselineMeanACK - 2
        % 위쪽 공간 부족 → error bar 오른쪽에 배치
        text(xACK(i) + sideOffset, meanSuc(i) + 1.0, sprintf('%.1f', meanSuc(i)), ...
            'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
            'FontSize', 9);
    else
        text(xACK(i), labelY, sprintf('%.1f', meanSuc(i)), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'FontSize', 9);
    end

end


%% ------------------------------------------------------------
% X-axis Labels
% ------------------------------------------------------------

xticks([xHit, xACK]);
xticklabels([displayNames; displayNames]);
xtickangle(0);


%% ------------------------------------------------------------
% Axis / Legend
% ------------------------------------------------------------

ylabel("Rate (%)", 'FontSize', 11);

ylim([0 100]);
yticks(0:10:100);
xlim([0.3, xACK(end) + 0.7]);

legend([hHit hACK], ["Jamming Hit Rate", "Target ACK Success Rate"], ...
    'Location', 'northwest', 'Orientation', 'horizontal');

grid on;
box on;
set(gca, 'FontSize', 10, 'LineWidth', 1.0, 'Layer', 'top', 'XGrid', 'off');

hold off;

exportgraphics(figC, 'final11_fig1c_overall_performance.pdf', 'ContentType', 'vector');
exportgraphics(figC, 'final11_fig1c_overall_performance.png', 'Resolution', 300);


%% ================================================================
%  Console Summary
% ================================================================

fprintf("\n");
fprintf("============================================================\n");
fprintf(" Attack Method Comparison — Loaded Results Summary\n");
fprintf("============================================================\n");

fprintf("%-22s : ACK %.2f%% ± %.2f (STD)\n", "No-Attack", baselineMeanACK, baselineStdACK);

for i = 1:numTechniques
    fprintf("%-22s : JHR %.2f%% ± %.2f | ACK %.2f%% ± %.2f | SINR %.3f dB ± %.3f\n", ...
        techniqueNames(i), meanHit(i), stdHit(i), meanSuc(i), stdSuc(i), ...
        meanSinr(i), stdSinr(i));
end

fprintf("============================================================\n");

fprintf("\n그래프 저장 완료:\n");
fprintf("  final11_fig1a_jamming_hit_rate.png/pdf\n");
fprintf("  final11_fig1b_ack_success_rate.png/pdf\n");
fprintf("  final11_fig1c_overall_performance.png/pdf\n");