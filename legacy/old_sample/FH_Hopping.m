clc;
clear;

global masterSeed;
rng('shuffle');
masterSeed = randi(10000);

MHz = 1e6;
GHz = 1e9;

%% 초기 환경 변수
N = 32;

jamHopList = [1 2 4 8 16];

BW_ch = 50 * MHz;
f_start = 26.5 * GHz;

T = 100000;

power = 10;
jammerPower = 10;

%% 결과 저장
error_random = zeros(1, length(jamHopList));
error_fixed = zeros(1, length(jamHopList));

%% =========================
%% sharedRandomFHP
%% =========================

for hIdx = 1:length(jamHopList)

    jamHopCount = jamHopList(hIdx);

    channels = createChannels(N, BW_ch, f_start);

    tx = Node(1, @sharedRandomFHP);
    rx = Node(2, @sharedRandomFHP);

    error_random(hIdx) = runSimulation( ...
        tx, rx, ...
        channels, ...
        N, T, ...
        power, jammerPower, ...
        jamHopCount);

end

%% =========================
%% fixedFHP
%% =========================

for hIdx = 1:length(jamHopList)

    jamHopCount = jamHopList(hIdx);

    channels = createChannels(N, BW_ch, f_start);

    tx = Node(1, @fixedFHP);
    rx = Node(2, @fixedFHP);

    error_fixed(hIdx) = runSimulation( ...
        tx, rx, ...
        channels, ...
        N, T, ...
        power, jammerPower, ...
        jamHopCount);

end

%% 그래프

figure('Color','w','Position',[100 100 900 600]);

semilogy(jamHopList,error_random,'-o','LineWidth',2.5,'MarkerSize',10,'MarkerFaceColor','w','Color',[0 0.2 0.9],'DisplayName','Shared Random FHP');
hold on;

semilogy(jamHopList,error_fixed,'-s','LineWidth',2.5,'MarkerSize',10,'MarkerFaceColor','w','Color',[0.9 0 0],'DisplayName','Fixed FHP');

grid on;
box on;

xlabel('Number of Jammed Channels per Slot (N = 32)','FontSize',16,'FontWeight','bold');
ylabel('Packet Error Rate','FontSize',16,'FontWeight','bold');

title('Impact of Jammed Channels on Packet Error Rate','FontSize',18,'FontWeight','bold');

legend('Location','northwest','FontSize',14,'Box','on');

set(gca,'FontSize',14,'LineWidth',1.3,'YMinorGrid','on','XMinorGrid','off');

xlim([0.5 16.5]);
ylim([1e-2 1]);

xticks(jamHopList);

%% =========================
%% Functions
%% =========================

function errorRate = runSimulation( ...
    tx, rx, ...
    channels, ...
    N, T, ...
    power, jammerPower, ...
    jamHopCount)

    ackCount = 0;
    nackCount = 0;

    for slot = 1:T

        payload = sprintf("DATA_SLOT_%d", slot);

        tx.createDataPacket(rx.id, payload);

        %% 채널 선택
        txChannel = tx.selectChannel(slot, channels);
        rxChannel = rx.selectChannel(slot, channels);

        %% 데이터 송신
        tx.sendPacket(power);

        %% 다중 채널 재밍
        jamChannelIds = randperm(N, jamHopCount);

        for j = 1:length(jamChannelIds)

            jamCh = channels{jamChannelIds(j)};

            jamSig = Signal( ...
                SignalType.JAMMING, ...
                [], ...
                jammerPower, ...
                999, ...
                jamCh.id);

            jamCh.addSignal(jamSig);

        end

        %% RX 수신
        if txChannel.id == rxChannel.id

            rx.receivePacket();

            %% ACK/NACK phase
            txChannel.reset();

            rx.sendPacket(power);

        end

        feedbackPkt = tx.receivePacket();

        if ~isempty(feedbackPkt)

            if feedbackPkt.type == PacketType.ACK
                ackCount = ackCount + 1;
            else
                nackCount = nackCount + 1;
            end

        end

        clearChannel(channels, N);

    end

    errorRate = nackCount / T;

end



function channels = createChannels(N, BW_ch, f_start)
    channels = cell(1, N);
    for i = 1:N
        centerFreq = f_start + (i-1) * BW_ch;
        channels{i} = Channel(i, centerFreq, BW_ch);
    end
end



function ch = fixedFHP(~, ~)
    ch = 1;
end

function ch = sharedRandomFHP(slot, N)
    global masterSeed;
    rng(masterSeed + slot);
    ch = randi(N);
end



function clearChannel(channels, N)
    for i = 1:N
        channels{i}.reset();
    end
end