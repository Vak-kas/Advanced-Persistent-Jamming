%% ==================== finalC.m ====================
% Diagnostic script: Why is the Comb jammer's JHR so low?
%
% This script is NOT for the paper's figures. It only runs the
% Comb baseline (TimeSlotC) and extracts the target beam's
% channel-selection histogram during the attack phase, split into
% early / mid / late thirds, to check whether the target avoids
% CH3/CH5 (the comb jammer's fixed channels) over time.

clc;
clear;
clear variables;
clear DebugHelper;
close all;

env;

combFixedChannels = [3 5];
numTrials = 5;   % final1.m/final3.m과 동일한 trial 수로 맞춤
totalSlots = numTimeSlots;
reconDurationUsed = reconnaissanceDuration;

fprintf("============================================================\n");
fprintf(" Comb Jammer Diagnostic: Target Channel-Selection Histogram\n");
fprintf("============================================================\n");
fprintf(" Trials                : %d\n", numTrials);
fprintf(" Reconnaissance         : %d\n", reconDurationUsed);
fprintf(" Attack starts at       : %d\n", reconDurationUsed + 1);
fprintf(" Comb fixed channels    : %s\n", mat2str(combFixedChannels));
fprintf("============================================================\n");

% 채널별 선택 횟수 누적 (trial 합산)
histAll   = zeros(1, numChannels);   % 전체 attack phase
histEarly = zeros(1, numChannels);   % attack phase 앞 1/3
histMid   = zeros(1, numChannels);   % attack phase 중간 1/3
histLate  = zeros(1, numChannels);   % attack phase 뒤 1/3

hitRatePerTrial = nan(1, numTrials);

for trial = 1:numTrials

    fprintf("\n--- Trial %d / %d ---\n", trial, numTrials);

    rng(trial);
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    apj = APJFactory.createAPJ(UTs, Beams, targetUTId, targetJammerDistance);

    timeSlotC = TimeSlotC(combFixedChannels);

    combLog = struct('slot', {}, 'observedChannel', {}, 'jammingChannels', {}, 'isAttackPhase', {});

    for slotIndex = 1:numTimeSlots
        combLog = timeSlotC.run(slotIndex, UTs, SatelliteNode, apj, ServiceChannels, ControlChannels, targetBeamIndex, combLog);
    end

    % ---- attack phase 슬롯만 추출 ----
    attackEntries = combLog([combLog.isAttackPhase]);
    attackChannels = [attackEntries.observedChannel];
    numAttackSlots = numel(attackChannels);

    thirdLen = floor(numAttackSlots / 3);
    earlyIdx = 1:thirdLen;
    midIdx   = (thirdLen+1):(2*thirdLen);
    lateIdx  = (2*thirdLen+1):numAttackSlots;

    for ch = 1:numChannels
        histAll(ch)   = histAll(ch)   + sum(attackChannels == ch);
        histEarly(ch) = histEarly(ch) + sum(attackChannels(earlyIdx) == ch);
        histMid(ch)   = histMid(ch)   + sum(attackChannels(midIdx) == ch);
        histLate(ch)  = histLate(ch)  + sum(attackChannels(lateIdx) == ch);
    end

    % ---- sanity check: JHR 재계산 (final3.m과 일치하는지 확인용) ----
    hitVec = nan(1, numAttackSlots);
    for i = 1:numAttackSlots
        jc = attackEntries(i).jammingChannels;
        if isempty(jc)
            continue;
        end
        hitVec(i) = double(any(attackChannels(i) == jc));
    end
    hitRatePerTrial(trial) = mean(hitVec, 'omitnan') * 100;
    fprintf("  JHR this trial: %.2f%%\n", hitRatePerTrial(trial));
end

%% ================================================================
%  Print Histogram (percentage of attack-phase slots per channel)
% ================================================================

histAll_pct   = 100 * histAll   / sum(histAll);
histEarly_pct = 100 * histEarly / sum(histEarly);
histMid_pct   = 100 * histMid   / sum(histMid);
histLate_pct  = 100 * histLate  / sum(histLate);

fprintf("\n============================================================\n");
fprintf(" Target Channel-Selection Histogram (attack phase, %% of slots)\n");
fprintf("============================================================\n");
fprintf("%-8s %-10s %-10s %-10s %-10s\n", "Channel", "Overall", "Early", "Mid", "Late");
for ch = 1:numChannels
    tag = "";
    if ismember(ch, combFixedChannels)
        tag = "  <-- Comb target";
    end
    fprintf("CH%-6d %-10.2f %-10.2f %-10.2f %-10.2f%s\n", ...
        ch, histAll_pct(ch), histEarly_pct(ch), histMid_pct(ch), histLate_pct(ch), tag);
end
fprintf("============================================================\n");

fprintf("\nMean JHR across trials: %.2f%% (should roughly match final1/final3 Comb result)\n", ...
    mean(hitRatePerTrial));

save('finalC_diagnostic.mat', ...
    'histAll', 'histEarly', 'histMid', 'histLate', ...
    'histAll_pct', 'histEarly_pct', 'histMid_pct', 'histLate_pct', ...
    'hitRatePerTrial', 'combFixedChannels', '-v7.3');


%% ================================================================
%  Local Functions (final3.m과 동일)
% ================================================================

function resetDebugStorage()
    DebugHelper.TargetUTStorage('reset', []);
end

function [ServiceChannels, ControlChannels] = buildChannels()
    env;
    ServiceChannels = Channel.empty(0, numChannels);
    ControlChannels = Channel.empty(0, numChannels);
    for channelIndex = 1:numChannels
        centerFreq_Hz = serviceBandStart_Hz + (channelIndex - 0.5) * channelSpacing_Hz;
        serviceChannelStart_Hz = centerFreq_Hz - channelBandwidth_Hz / 2;
        serviceChannelEnd_Hz = centerFreq_Hz + channelBandwidth_Hz / 2;
        ServiceChannels(channelIndex) = Channel(channelIndex, ChannelType.Service, serviceChannelStart_Hz, serviceChannelEnd_Hz);
        ControlChannels(channelIndex) = Channel(channelIndex, ChannelType.Control, 1, 2);
    end
end

function [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork()
    env;
    satellitePosition = [0 0 satelliteAltitude];
    SatelliteNode = Satellite(9999, satellitePosition, numBeams);
    Beams = BeamFactory.createBeams(numBeams, maxBeamFootprintDiameter, beamRadius, beamSpacing, beamMaxGain_dBi, beam3dBWidth_deg, beamEIRPDensity_dBW_per_MHz, channelBandwidth_Hz);
    for beamIndex = 1:numBeams
        SatelliteNode.addBeam(Beams(beamIndex));
    end
    UTs = UTFactory.createUTs(Beams, numUTs);
    targetBeamIndex = find([Beams.AssociatedUTId] == targetUTId, 1);
    if isempty(targetBeamIndex)
        error("finalC:TargetBeamNotFound", "targetUTId 에 연결된 Beam을 찾을 수 없습니다.");
    end
end