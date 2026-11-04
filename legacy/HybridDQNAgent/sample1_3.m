clc;
clear;
rng('shuffle');

MHz = 1e6;
GHz = 1e9;

%% Parameters
N = 20;
J = 1;
K = 10;
T = 1000;

area = [2500, 2500, 0];
pairDistance = 200;

BW_ch = 50 * MHz;
f_start = 26.5 * GHz;
f_end = 29.5 * GHz;
interferenceRange = 700;

%% Time Parameters
Tc_ms = 10;
Tj_ms = 5;

%% Physical Parameters
power = 50;
jammerPower = 1000;

pathLossExponent = 2;

noisePower_dBm = -80;
thermalNoise = 10^(noisePower_dBm / 10);

betaThreshold_dB = 10;
betaThreshold = 10^(betaThreshold_dB / 10);

%% DQN Parameters
Phi_ms = 100;
D = 5000;
gamma = 0.8;

etaList = [0 0.2 0.4 0.6 0.8 1.0];
numRuns = 5;

epsilon_start = 1.0;
epsilon_min   = 0.01;
epsilon_decay = 0.995;

batchSize = 128;
learnRate = 0.0005;

phi = Phi_ms / Tc_ms;

%% Result Storage
NCT_all_runs = zeros(length(etaList), numRuns, T);
NCT_mean_all = zeros(length(etaList), T);
NCT_smooth_all = zeros(length(etaList), T);

masterSeed = randi(1000000);

%% Eta x Run Experiment
for etaIdx = 1:length(etaList)

    eta = etaList(etaIdx);

    fprintf("\n\n================ ETA = %.1f ================\n", eta);

    for runIdx = 1:numRuns

        fprintf("\n---------- Run %d / %d ----------\n", runIdx, numRuns);

        rng(masterSeed + runIdx);

        %% Initialize Environment
        channels = createChannels(K, BW_ch, f_start);
        channelModel = ChannelModel(pathLossExponent);

        [txNodes, rxNodes] = createNodes( ...
            N, area, power, @randomFHP, pairDistance, Tc_ms);

        jammer = Jammer( ...
            1001, ...
            @combJammerFHP, ...
            [1250, 1250, 0], ...
            jammerPower, ...
            "comb", ...
            Tc_ms, ...
            Tj_ms ...
        );

        clearChannel(channels);

        NCT = zeros(1, T);
        epsilon = epsilon_start;

        %% Agent 생성
        agents = cell(N, 1);

        for n = 1:N
            agents{n} = HybridDQNAgent( ...
                n, ...
                K, ...
                phi, ...
                D, ...
                gamma, ...
                eta, ...
                epsilon, ...
                batchSize, ...
                learnRate ...
            );
        end

        %% Simulation Start
        for slot = 1:T

            clearChannel(channels);

            channelModel.update(txNodes, rxNodes, jammer, channels);

            success = zeros(N, 1);
            O_t_list = cell(N, 1);
            actionList = zeros(N, 1);

            %% Channel Selection
            for n = 1:N
                O_t_list{n} = agents{n}.getObservation();

                action = agents{n}.selectAction();
                actionList(n) = action;

                txNodes{n}.setChannelById(action, channels);
            end

            %% DATA Packet 생성
            for n = 1:N
                payload = sprintf("DATA_SLOT_%d", slot);
                txNodes{n}.createDataPacket(n, payload);
            end

            %% DATA 송신
            for n = 1:N
                txNodes{n}.sendPacket();
            end

            %% Jammer Signal 추가
            jammer.selectChannel(slot, channels);
            jammer.jam(slot);

            %% Rx DATA 수신 및 ACK/NACK 생성
            for n = 1:N
                rxNodes{n}.receivedPacket( ...
                    channels, ...
                    betaThreshold, ...
                    thermalNoise, ...
                    channelModel ...
                );
            end

            %% Rx ACK/NACK 송신
            for n = 1:N
                rxNodes{n}.sendPacket();
            end

            %% Tx ACK/NACK 수신
            for n = 1:N
                success(n) = txNodes{n}.receiveAck( ...
                    betaThreshold, ...
                    thermalNoise, ...
                    channelModel ...
                );
            end

            %% Spectrum Sensing
            o_next_list = cell(N, 1);

            for n = 1:N
                o_next_list{n} = senseSpectrum( ...
                    txNodes{n}, ...
                    channels, ...
                    channelModel, ...
                    thermalNoise ...
                );
            end

            %% Experience 저장 및 Train
            for n = 1:N

                agents{n}.updateObservation(o_next_list{n});
                O_next = agents{n}.getObservation();

                [r_u, r_j] = getReward(success(n));

                agents{n}.storeExperience( ...
                    O_t_list{n}, ...
                    actionList(n), ...
                    r_u, ...
                    r_j, ...
                    O_next ...
                );

                agents{n}.train();
            end

            %% NCT 저장
            NCT(slot) = mean(success);

            %% Epsilon Decay
            epsilon = max(epsilon_min, epsilon * epsilon_decay);

            for n = 1:N
                agents{n}.epsilon = epsilon;
            end

        end

        NCT_all_runs(etaIdx, runIdx, :) = NCT;

        fprintf("ETA %.1f | Run %d | Mean NCT 800~1000 = %.4f | Mean NCT 900~1000 = %.4f\n", ...
            eta, ...
            runIdx, ...
            mean(NCT(800:1000)), ...
            mean(NCT(900:1000)) ...
        );

    end

    %% eta별 5회 평균
    NCT_mean = squeeze(mean(NCT_all_runs(etaIdx, :, :), 2)).';

    NCT_mean_all(etaIdx, :) = NCT_mean;

    %% 네가 쓰던 그래프 방식: 후반 고점 기준 scaled + EMA
    NCT_scaled = NCT_mean / max(NCT_mean(500:end));
    NCT_scaled = min(1.0, NCT_scaled);

    alpha = 0.02;
    NCT_smooth = zeros(1, T);
    NCT_smooth(1) = 0;

    for t = 2:T
        NCT_smooth(t) = (1 - alpha) * NCT_smooth(t-1) + alpha * NCT_scaled(t);
    end

    NCT_smooth_all(etaIdx, :) = NCT_smooth;

    fprintf("\nETA %.1f | 5-run Mean 800~1000 = %.4f | 5-run Mean 900~1000 = %.4f\n", ...
        eta, ...
        mean(NCT_mean(800:1000)), ...
        mean(NCT_mean(900:1000)) ...
    );

end

%% Figure
slots = 1:T;

figure('Position', [100, 100, 750, 600]);
hold on;
grid on;
box on;

plot(slots, NCT_smooth_all(1, :), 'LineWidth', 3.0);
plot(slots, NCT_smooth_all(2, :), 'LineWidth', 3.0);
plot(slots, NCT_smooth_all(3, :), 'LineWidth', 3.0);
plot(slots, NCT_smooth_all(4, :), 'LineWidth', 3.0);
plot(slots, NCT_smooth_all(5, :), 'LineWidth', 3.0);
plot(slots, NCT_smooth_all(6, :), 'LineWidth', 3.0);

xlabel('Communication time slot', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Normalized communication throughput', 'FontSize', 12, 'FontWeight', 'bold');
title('NCT Performance under Comb Jamming', 'FontSize', 13, 'FontWeight', 'bold');

xlim([0 1000]);
ylim([0 1.05]);

legend( ...
    'Weight coefficient = 0', ...
    'Weight coefficient = 0.2', ...
    'Weight coefficient = 0.4', ...
    'Weight coefficient = 0.6', ...
    'Weight coefficient = 0.8', ...
    'Weight coefficient = 1', ...
    'Location', 'southeast', ...
    'FontSize', 10 ...
);

set(gca, 'FontSize', 11, 'LineWidth', 1.2);
axis square;

%% Final Mean NCT 출력
fprintf("\n\n================ Final Mean NCT over 5 Runs ================\n");

for etaIdx = 1:length(etaList)

    NCT_mean = NCT_mean_all(etaIdx, :);

    fprintf("eta = %.1f | Raw Mean 800~1000 = %.4f | Raw Mean 900~1000 = %.4f | Raw Max 500~1000 = %.4f\n", ...
        etaList(etaIdx), ...
        mean(NCT_mean(800:1000)), ...
        mean(NCT_mean(900:1000)), ...
        max(NCT_mean(500:end)) ...
    );

end

%% Strategy
function ch = fixedFHP(slot, N)
    ch = 1;
end

function ch = randomFHP(slot, N)
    ch = randi(N);
end

function ch = sweptJammerFHP(slot, K, Tc_ms, Tj_ms)

    slotStartAbs_ms = (slot - 1) * Tc_ms;
    slotEndAbs_ms   = slot * Tc_ms;

    ch = [];
    abs_t = slotStartAbs_ms;

    while abs_t < slotEndAbs_ms
        jamIndex = floor(abs_t / Tj_ms);
        channelId = mod(jamIndex, K) + 1;

        ch(end+1) = channelId;

        nextSwitchAbs_ms = (jamIndex + 1) * Tj_ms;
        abs_t = min(slotEndAbs_ms, nextSwitchAbs_ms);
    end

    ch = unique(ch, 'stable');

end

function ch = combJammerFHP(slot, K, Tc_ms, Tj_ms)
    ch = [1, 2, 3];
end

%% Functions
function channels = createChannels(N, BW_ch, f_start)

    channels = cell(1, N);

    for i = 1:N
        centerFreq = f_start + (i - 1) * BW_ch;
        channels{i} = Channel(i, centerFreq, BW_ch);
    end

end

function clearChannel(channels)

    for i = 1:length(channels)
        channels{i}.reset();
    end

end

function clearCommSignals(channels)

    for i = 1:length(channels)
        channels{i}.removeCommSignals();
    end

end

function [txNodes, rxNodes] = createNodes(N, area, power, FHP, pairDistance, Tc_ms)

    txNodes = cell(N, 1);
    rxNodes = cell(N, 1);

    txPositions = [
         110,  320, 0;
         590,  410, 0;
         490,  700, 0;
         990,  900, 0;
        1390,  590, 0;
        1900,  500, 0;
        2100,  100, 0;
        2190,  910, 0;
        1900, 1310, 0;
        1300, 1310, 0;
        1700, 1590, 0;
        2100, 1910, 0;
        2270, 2320, 0;
        1820, 2200, 0;
        1200, 1910, 0;
         900, 1500, 0;
         180, 1100, 0;
         400, 1590, 0;
         590, 2000, 0;
         310, 2410, 0
    ];

    numPredefined = size(txPositions, 1);

    for i = 1:N

        if i <= numPredefined
            txPosition = txPositions(i, :);
        else
            txPosition = [rand() * area(1), rand() * area(2), rand() * area(3)];
        end

        if ~isempty(pairDistance)
            rxPosition = txPosition + [randn() * pairDistance, randn() * pairDistance, 0];
            rxPosition = max(min(rxPosition, area), [0 0 0]);
        else
            rxPosition = [rand() * area(1), rand() * area(2), rand() * area(3)];
        end

        txNodes{i} = Node(i, NodeType.Tx, txPosition, power, FHP, Tc_ms);
        rxNodes{i} = Node(i, NodeType.Rx, rxPosition, power, [], Tc_ms);

    end

end

function [r_u, r_j] = getReward(success)

    if success == 1
        r_u = 5;
        r_j = 1;
    else
        r_u = -1;
        r_j = -10;
    end

end

function o_t = senseSpectrum(txNode, channels, channelModel, thermalNoise)

    K = length(channels);
    o_t = zeros(1, K);

    for k = 1:K

        channel = channels{k};
        signals = channel.getSignals();

        totalPower = thermalNoise;

        for i = 1:length(signals)

            sig = signals{i};

            gain = channelModel.getGain( ...
                sig.txRole, ...
                sig.txNodeId, ...
                txNode.role, ...
                txNode.id, ...
                sig.txChannelId ...
            );

            totalPower = totalPower + sig.txPower * gain;

        end

        p_dBm = 10 * log10(totalPower + eps);

        o_t(k) = (p_dBm + 80) / 80;
        o_t(k) = max(0, min(1, o_t(k)));

    end

end