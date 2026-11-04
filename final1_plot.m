%% ==================== final1_plot.m ====================
% final1.m 결과(.mat)를 로드해서 정찰 기간(T_R) 스윕 그래프를 그린다 (논문 Table 3의 시각화).
% 아래 파일명을 사용할 결과 파일로 바꿔서 실행 (final1.m은 results/final1_results_<N>trials.mat 로 저장).

clc; clear; close all;

load('results/final1_results.mat');

figure('Color', 'w', 'Position', [100 100 850 430]);
hold on;

offset = 15;
colorJHR = [0 0.45 0.74];
colorACK = [0.85 0.33 0.10];

xJ = reconDurationList - offset;
xA = reconDurationList + offset;

% ----- 연결선: T_R=0 -> 500 구간은 점선, 이후는 실선 -----
plot(xJ(1:2), meanHit(1:2), '--', 'Color', colorJHR, 'LineWidth', 1.3, 'HandleVisibility', 'off');
plot(xJ(2:end), meanHit(2:end), '-', 'Color', colorJHR, 'LineWidth', 1.5, 'HandleVisibility', 'off');

plot(xA(1:2), meanSuc(1:2), '--', 'Color', colorACK, 'LineWidth', 1.3, 'HandleVisibility', 'off');
plot(xA(2:end), meanSuc(2:end), '-', 'Color', colorACK, 'LineWidth', 1.5, 'HandleVisibility', 'off');

% ----- 점 + 95% CI -----
errorbar(xJ, meanHit, ciHit, 'o', 'LineWidth', 1.5, 'MarkerSize', 7, 'CapSize', 8, ...
    'Color', colorJHR, 'MarkerFaceColor', 'w');
errorbar(xA, meanSuc, ciSuc, 's', 'LineWidth', 1.5, 'MarkerSize', 7, 'CapSize', 8, ...
    'Color', colorACK, 'MarkerFaceColor', 'w');

xlabel("Reconnaissance Duration (decision epochs)");
ylabel("Rate (%)");
legend(["Jamming Hit Rate", "Target ACK Success Rate"], 'Location', 'best');
xticks(reconDurationList);
xlim([-150 2150])
ylim([0 100]);
grid on; box on;
hold off;