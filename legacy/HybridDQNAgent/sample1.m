clc;
clear;

MHz = 1e6;
GHz = 1e9;

%% Parameters
N = 20;
K = 10;
T = 300;

area = [2500, 2500, 0];
pairDistance = [];

BW_ch = 50 * MHz;
f_start = 26.5 * GHz;

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
phi = Phi_ms / Tc_ms;

D = 5000;
gamma = 0.8;
etaList = [0, 0.2, 0.5, 0.8, 1.0];

epsilon = 0;
batchSize = 128;
learnRate = 0.001;

numRuns = 10;

%% Result Storage
NCT_all = zeros(length(etaList), numRuns, T);

%% Main Experiment
for e = 1:length(etaList)

    eta = etaList(e);
    fprintf("\n================ ETA = %.1f ================\n", eta);

    for run = 1:numRuns

        fprintf("Run %d / %d\n", run, numRuns);

        %% Initialize Environment
        channels = createChannels(K, BW_ch, f_start);
        channelModel = ChannelModel(pathLossExponent);

        [txNodes, rxNodes] = createNodes( ...
            N, area, power, @randomFHP, pairDistance, Tc_ms);

        jammer = Jammer( ...
            1001, ...
            @sweptJammerFHP, ...
            [1250, 1250, 0], ...
            jammerPower, ...
            "swept", ...
            Tc_ms, ...
            Tj_ms);

        clearChannel(channels);

        %% Agent 생성
        agents = cell(N, 1);

        for n = 1:N
            agents{n} = HybridDQNAgent( ...
                n, K, phi, D, gamma, eta, epsilon, batchSize, learnRate);
        end

        NCT = zeros(1, T);

        %% Simulation Start
        for slot = 1:T

            clearChannel(channels);
            channelModel.update(txNodes, rxNodes, jammer);

            success = zeros(N, 1);

            O_t_list = cell(N, 1);
            actionList = zeros(N, 1);

            %% Tx Channel Selection by Agent
            for n = 1:N
                O_t_list{n} = agents{n}.getObservation();
                action = agents{n}.selectAction();

                actionList(n) = action;
                txNodes{n}.setChannelById(action, channels);
            end

            %% Data Packet 생성
            for n = 1:N
                payload = sprintf("DATA_SLOT_%d", slot);
                txNodes{n}.createDataPacket(n, payload);
            end

            %% Data 송신
            for n = 1:N
                txNodes{n}.sendPacket();
            end

            %% Jammer Signal 추가
            jammer.selectChannel(slot, channels);
            jammer.jam(slot);

            %% Spectrum Sensing
            o_next_list = cell(N, 1);

            for n = 1:N
                o_next_list{n} = senseSpectrum( ...
                    txNodes{n}, channels, channelModel, thermalNoise);
            end

            %% Rx Data 수신 및 ACK/NACK 생성
            for n = 1:N
                rxNodes{n}.receivedPacket( ...
                    channels, betaThreshold, thermalNoise, channelModel);
            end

            %% DATA 신호 제거, JAMMING 유지
            clearCommSignals(channels);

            %% ACK/NACK 송신
            for n = 1:N
                rxNodes{n}.sendPacket();
            end

            %% Tx ACK/NACK 수신
            for n = 1:N
                success(n) = txNodes{n}.receiveAck( ...
                    betaThreshold, thermalNoise, channelModel);
            end

            %% Experience 저장 및 학습
            for n = 1:N
                agents{n}.updateObservation(o_next_list{n});
                O_next = agents{n}.getObservation();

                [r_u, r_j] = getReward(success(n));

                agents{n}.storeExperience( ...
                    O_t_list{n}, ...
                    actionList(n), ...
                    r_u, ...
                    r_j, ...
                    O_next);

                agents{n}.train();
            end

            %% NCT 저장
            NCT(slot) = mean(success);

        end

        NCT_all(e, run, :) = NCT;

    end
end

%% Plot Result
windowSize = 50;

figure;
hold on;
grid on;
box on;

for e = 1:length(etaList)

    NCT_mean = squeeze(mean(NCT_all(e, :, :), 2));
    NCT_smooth = movmean(NCT_mean, windowSize);

    plot(1:T, NCT_smooth, 'LineWidth', 2.5);

end

xlabel('Communication time slot');
ylabel('Normalized communication throughput');
title('NCT convergence for different weight coefficients');

legend( ...
    'Weight coefficient = 0', ...
    'Weight coefficient = 0.2', ...
    'Weight coefficient = 0.5', ...
    'Weight coefficient = 0.8', ...
    'Weight coefficient = 1', ...
    'Location', 'southeast');

ylim([0 1]);


%% Strategy
function ch = fixedFHP(slot, N)
    ch = 1;
end

function ch = randomFHP(slot, N)
    ch = randi(N);
end

function ch = sweptJammerFHP(slot, K, Tc_ms, Tj_ms)

    slotStartAbs_ms = (slot - 1) * Tc_ms;
    slotEndAbs_ms = slot * Tc_ms;

    ch = [];
    abs_t = slotStartAbs_ms;

    while abs_t < slotEndAbs_ms

        jamIndex = floor(abs_t / Tj_ms);
        channelId = mod(jamIndex, K) + 1;

        ch(end + 1) = channelId;

        nextSwitchAbs_ms = (jamIndex + 1) * Tj_ms;
        abs_t = min(slotEndAbs_ms, nextSwitchAbs_ms);

    end

    ch = unique(ch, 'stable');

end

function ch = combJammerFHP(slot, K, combChannels)
    ch = combChannels;
end


%% Utility Functions
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

    for i = 1:N

        txPosition = [rand() * area(1), rand() * area(2), rand() * area(3)];

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

    if success
        r_u = 5;
        r_j = 1;
    else
        r_u = -1;
        r_j = -10;
    end

end

function o_t = senseSpectrum(rxNode, channels, channelModel, thermalNoise)

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
                rxNode.role, ...
                rxNode.id);

            totalPower = totalPower + sig.txPower * gain;

        end

        o_t(k) = 10 * log10(totalPower);

    end

end