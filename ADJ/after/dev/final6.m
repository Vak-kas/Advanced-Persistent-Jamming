%% ==================== final6.m ====================
% APJ-Target Distance Sensitivity Analysis — Data Generation (RQ4)
%
% "APJ와 Target 간 관측 위치 차이가 커져도 공격이 가능한가?"
%
% Experiment:
%   1) No-Attack baseline (거리 무관, 참고용 기준선)
%   2) APJ-Target distance sweep: [0.01, 0.1, 0.5, 1, 5, 10, 20] km
%
% Metrics:
%   - Top-2 Jamming Hit Rate (Attack phase)
%   - Target UT ACK Success Rate (Attack phase)
%   - Target UT SINR (Attack phase, 보조지표)
%
% Statistical reporting:
%   - numTrials 반복, 95% CI (t-분포 기반)
%
% 이 스크립트는 시뮬레이션 실행 + raw 데이터 저장만 담당한다.
% 그래프는 final6_plot.m에서 저장된 .mat을 로드해서 그린다.

clc;
clear;
clear variables;
clear DebugHelper;
close all;

%% ================================================================
%  Configuration
% ================================================================

distanceList_km = [0.01, 0.1, 0.5, 1, 5, 10, 20];
numDistances = numel(distanceList_km);

% Final paper: >=5 recommended / Debug: 1~3
numTrials = 5;

baseSeed = 100;
trialSeeds = baseSeed + (0:numTrials-1);


%% ================================================================
%  Load environment once
% ================================================================

env;

fprintf("\n============================================================\n");
fprintf(" APJ-Target Distance Sweep\n");
fprintf("============================================================\n");
fprintf(" Distance list (km)    : %s\n", mat2str(distanceList_km));
fprintf(" Number of trials      : %d\n", numTrials);
fprintf(" Total slots           : %d\n", numTimeSlots);
fprintf(" Reconnaissance        : %d\n", reconnaissanceDuration);
fprintf(" Attack starts at      : %d\n", reconnaissanceDuration + 1);
fprintf("============================================================\n");


%% ================================================================
%  Result Storage
% ================================================================

hitRateResults = nan(numDistances, numTrials);
ackRateResults = nan(numDistances, numTrials);
sinrResults    = nan(numDistances, numTrials);

% No-Attack baseline
baselineAckResults = nan(1, numTrials);


%% ================================================================
%  No-Attack Baseline
% ================================================================

fprintf("\n============================================================\n");
fprintf(" NO-ATTACK BASELINE\n");
fprintf("============================================================\n");

for trial = 1:numTrials

    seed = trialSeeds(trial);
    baselineAckResults(trial) = runNoAttack(seed);

end

baselineMeanACK = mean(baselineAckResults, 'omitnan');
baselineStdACK  = std(baselineAckResults, 0, 'omitnan');
baselineCiACK   = compute95CI_1D(baselineAckResults);

fprintf("\n------------------------------------------------------------\n");
fprintf(" No-Attack ACK Success Rate = %.2f%% ± %.2f (95%% CI), n=%d\n", ...
    baselineMeanACK, baselineCiACK, numTrials);
fprintf("------------------------------------------------------------\n");


%% ================================================================
%  Distance Sweep
% ================================================================

for distIdx = 1:numDistances

    distance_m = distanceList_km(distIdx) * 1e3;

    fprintf("\n");
    fprintf("############################################################\n");
    fprintf(" Distance = %.2f km\n", distanceList_km(distIdx));
    fprintf("############################################################\n");

    for trial = 1:numTrials

        seed = trialSeeds(trial);

        [hitRateResults(distIdx, trial), ackRateResults(distIdx, trial), sinrResults(distIdx, trial)] = ...
            runDistanceTrial(seed, distance_m);

    end
end


%% ================================================================
%  Aggregate Statistics
% ================================================================

meanHit = mean(hitRateResults, 2, 'omitnan');
stdHit  = std(hitRateResults, 0, 2, 'omitnan');

meanAck = mean(ackRateResults, 2, 'omitnan');
stdAck  = std(ackRateResults, 0, 2, 'omitnan');

meanSinr = mean(sinrResults, 2, 'omitnan');
stdSinr  = std(sinrResults, 0, 2, 'omitnan');

ciHit  = compute95CI(hitRateResults);
ciAck  = compute95CI(ackRateResults);
ciSinr = compute95CI(sinrResults);


%% ================================================================
%  Print Final Results
% ================================================================

fprintf("\n");
fprintf("============================================================\n");
fprintf(" APJ-Target Distance Sweep — Final Results\n");
fprintf("============================================================\n");

fprintf("%-14s : ACK %.2f%% ± %.2f (95%% CI)\n", "No-Attack", baselineMeanACK, baselineCiACK);

for i = 1:numDistances
    fprintf( ...
        "Distance=%6.2fkm : JHR %.2f%% ± %.2f | ACK %.2f%% ± %.2f | SINR %.3f dB ± %.3f\n", ...
        distanceList_km(i), meanHit(i), ciHit(i), meanAck(i), ciAck(i), meanSinr(i), ciSinr(i));
end

fprintf("============================================================\n");


%% ================================================================
%  SAVE ALL RESULTS
% ================================================================

save('final6_results.mat', ...
    'distanceList_km', 'numDistances', 'numTrials', 'trialSeeds', ...
    'hitRateResults', 'ackRateResults', 'sinrResults', ...
    'meanHit', 'stdHit', 'meanAck', 'stdAck', 'meanSinr', 'stdSinr', ...
    'ciHit', 'ciAck', 'ciSinr', ...
    'baselineAckResults', 'baselineMeanACK', 'baselineStdACK', 'baselineCiACK', ...
    '-v7.3');

fprintf("\nNumerical results saved: final6_results.mat\n");
fprintf("그래프는 final6_plot.m을 실행해서 그리세요 (재시뮬레이션 불필요).\n");


%% ================================================================
%  Local Functions
% ================================================================

function ackRate = runNoAttack(seed)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    % No-Attack에서는 거리 자체가 결과에 영향 없음(재밍 안 하므로) → 임의 참조거리 사용
    referenceDistance_m = 1e3;
    apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, referenceDistance_m);

    timeSlotDE = TimeSlotDE(2, reconnaissanceDuration);
    timeSlotDE.EnableJamming = false;

    divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
        'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
        'observedChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'isAttackPhase', {}, 'jammingChannels', {});
    channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

    for slotIndex = 1:numTimeSlots
        [divergenceLog, channelLog] = timeSlotDE.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);
    end

    ackRate = NaN;
    evalUTData = DebugHelper.TargetUTStorage('get', []);
    if ~isempty(evalUTData) && ~isempty(evalUTData.slots)
        attackIdx = logical(evalUTData.isAttackPhase);
        if any(attackIdx)
            ackRate = mean(evalUTData.isACK(attackIdx)) * 100;
        end
    end

    fprintf("  [No-Attack, Seed=%d] ACK=%.2f%%\n", seed, ackRate);
end


function [hitRate, ackRate, sinrDb] = runDistanceTrial(seed, distance_m)

    rng(seed, 'twister');
    env;
    resetDebugStorage();

    [ServiceChannels, ControlChannels] = buildChannels();
    [SatelliteNode, Beams, UTs, targetBeamIndex] = buildNetwork();

    apjd = APJFactory.createAPJ(UTs, Beams, targetUTId, distance_m);

    timeSlotDE = TimeSlotDE(2, reconnaissanceDuration);
    timeSlotDE.EnableJamming = true;

    divergenceLog = struct('slot', {}, 'lossA', {}, 'lossB', {}, 'qCosSim', {}, 'argmaxMatch', {}, ...
        'weightDiffNorm', {}, 'weightNormA', {}, 'weightNormB', {}, 'qA', {}, 'qB', {}, 'qL2Dist', {}, ...
        'observedChannel', {}, 'actualACK', {}, 'estimatedOutcome', {}, 'isAttackPhase', {}, 'jammingChannels', {});
    channelLog = struct('slot', {}, 'channel', {}, 'epsilon', {}, 'method', {}, 'qValues', {});

    for slotIndex = 1:numTimeSlots
        [divergenceLog, channelLog] = timeSlotDE.run(slotIndex, UTs, SatelliteNode, apjd, ServiceChannels, ControlChannels, targetBeamIndex, divergenceLog, channelLog);
    end

    isAttackPhaseLog = [divergenceLog.isAttackPhase];
    observedChannels = [divergenceLog.observedChannel];
    attackIdx = find(isAttackPhaseLog);

    hitCount = 0; totalCount = 0;
    for idx = attackIdx
        jc = divergenceLog(idx).jammingChannels;
        if isempty(jc), continue; end
        totalCount = totalCount + 1;
        if any(observedChannels(idx) == jc)
            hitCount = hitCount + 1;
        end
    end

    hitRate = NaN;
    if totalCount > 0
        hitRate = hitCount / totalCount * 100;
    end

    ackRate = NaN;
    sinrDb  = NaN;
    evalUTData = DebugHelper.TargetUTStorage('get', []);
    if ~isempty(evalUTData) && ~isempty(evalUTData.slots)
        evalUTAttackIdx = logical(evalUTData.isAttackPhase);
        if any(evalUTAttackIdx)
            ackRate = mean(evalUTData.isACK(evalUTAttackIdx)) * 100;
            sinrDb  = mean(evalUTData.SINR_dB(evalUTAttackIdx), 'omitnan');
        end
    end

    fprintf("  [Distance=%.2fkm, Seed=%d] JHR=%.2f%% | ACK=%.2f%% | SINR=%.3fdB\n", ...
        distance_m/1e3, seed, hitRate, ackRate, sinrDb);
end


%% ================================================================
%  95% CI for aggregate results (N distances x N trials)
% ================================================================

function ci = compute95CI(data)

    numConditions = size(data, 1);
    ci = nan(numConditions, 1);

    for i = 1:numConditions
        x = data(i, :);
        x = x(~isnan(x));
        n = numel(x);
        if n <= 1
            continue;
        end
        sem = std(x, 0) / sqrt(n);
        tCritical = tinv(0.975, n - 1);
        ci(i) = tCritical * sem;
    end
end


%% ================================================================
%  95% CI (scalar vector, e.g. baseline)
% ================================================================

function ci = compute95CI_1D(data)

    x = data(~isnan(data));
    n = numel(x);
    ci = NaN;
    if n <= 1
        return;
    end
    sem = std(x, 0) / sqrt(n);
    tCritical = tinv(0.975, n - 1);
    ci = tCritical * sem;
end


%% ================================================================
%  Reset DebugHelper
% ================================================================

function resetDebugStorage()
    DebugHelper.TargetUTStorage('reset', []);
end


%% ================================================================
%  Build Channels
% ================================================================

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


%% ================================================================
%  Build Network
% ================================================================

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
        error("final6:TargetBeamNotFound", "targetUTId 에 연결된 Beam을 찾을 수 없습니다.");
    end
end