classdef TimeSlot
    properties
        UseAgent
        ReconnaissanceDuration
        Debug
    end

    methods
        % ========== 생성자 ========== %
        function obj = TimeSlot()
            env;

            obj.UseAgent = useAgent;
            obj.ReconnaissanceDuration = reconnaissanceDuration;
            obj.Debug = isDebug;
        end


        % ============================================================
        % Time Slot 실행
        % ============================================================
        function [result, actualTargetACK, shadowResult] = run( ...
                obj, slotIndex, UTs, Satellites, APJ, ...
                ServiceChannels, ControlChannels)

            % --------------------------------------------------------
            % Shadowing 결과 초기화
            % --------------------------------------------------------
            shadowResult = struct( ...
                'ActualChannel', [], ...
                'UTGreedyChannel', [], ...
                'APJPredictedChannel', [], ...
                'ActualPredictionCorrect', false, ...
                'GreedyAgreementCorrect', false, ...
                'QMargin', [], ...
                'QCorrelation', [], ...
                'SpearmanCorrelation', [], ...
                'UTGreedyRankInAPJ', [], ...
                'TopKHit', []);

            DebugHelper.printTimeSlot(slotIndex);


            %% =======================================================
            % 0. 채널 센싱 및 이전 Transition 완성
            % ========================================================

            % UT Observation
            for utIndex = 1:numel(UTs)

                observation = ...
                    UTs(utIndex).ObservationManager.observe( ...
                        ServiceChannels, UTs);

                UTs(utIndex).Agent.setCurrentState(observation);

                UTs(utIndex).Agent.completeTransition();
            end


            % APJ Observation
            apjObservation = ...
                APJ.ObservationManager.observe( ...
                    ServiceChannels, UTs);

            APJ.Agent.setCurrentState(apjObservation);

            APJ.Agent.completeTransition();


            % Debug
            % DebugHelper.printObservation(UTs(1), ServiceChannels, UTs);
            % DebugHelper.printObservation(APJ, ServiceChannels, UTs);



            %% =======================================================
            % 1. DQN 학습
            % ========================================================

            % ---------------- UT ----------------
            if obj.UseAgent

                for utIndex = 1:numel(UTs)

                    lossValue = ...
                        UTs(utIndex).Agent.train();

                    % Target UT만 출력
                    if obj.Debug && ...
                            utIndex == APJ.TargetUTId && ...
                            ~isempty(lossValue)

                        DebugHelper.printTraining( ...
                            UTs(utIndex).Id, ...
                            UTs(utIndex).Agent.ReplayBuffer.Count, ...
                            UTs(utIndex).Agent.TrainingStep, ...
                            lossValue);
                    end
                end
            end


            % ---------------- APJ ----------------
            apjLossValue = [];

            if slotIndex <= obj.ReconnaissanceDuration

                apjLossValue = ...
                    APJ.Agent.train();

            end


            if obj.Debug && ~isempty(apjLossValue)

                DebugHelper.printTraining( ...
                    APJ.Id, ...
                    APJ.Agent.ReplayBuffer.Count, ...
                    APJ.Agent.TrainingStep, ...
                    apjLossValue);
            end



            %% =======================================================
            % 2. 채널 초기화
            % ========================================================

            obj.clearChannels( ...
                ServiceChannels, ...
                ControlChannels);



            %% =======================================================
            % 3. UT 채널 선택
            % ========================================================

            for utIndex = 1:numel(UTs)

                if obj.UseAgent

                    % Target UT
                    if utIndex == APJ.TargetUTId

                        selectedChannel = ...
                            UTs(utIndex).Agent.selectAction(obj.Debug);

                    % 나머지 UT
                    else

                        selectedChannel = ...
                            UTs(utIndex).selectRuleBasedChannel();

                    end

                else

                    selectedChannel = ...
                        randi(numel(ServiceChannels));

                end


                UTs(utIndex).SelectedChannel = ...
                    selectedChannel;
            end



            %% =======================================================
            % 4. UT Data 전송
            % ========================================================

            dataPackets = ...
                cell(1, numel(UTs));


            for utIndex = 1:numel(UTs)

                selectedChannel = ...
                    UTs(utIndex).SelectedChannel;


                dataPackets{utIndex} = Packet( ...
                    PacketType.DATA, ...
                    NodeType.UT, ...
                    utIndex, ...
                    NodeType.Satellite, ...
                    utIndex, ...
                    ChannelType.Service, ...
                    selectedChannel);
            end


            % Service Channel에 Packet 등록
            for utIndex = 1:numel(UTs)

                selectedChannel = ...
                    dataPackets{utIndex}.ChannelId;

                ServiceChannels(selectedChannel).addPacket( ...
                    dataPackets{utIndex});
            end



            %% =======================================================
            % 5. APJ 동작
            % ========================================================

            % Target UT 실제 사용 채널 관측
            observedChannel = ...
                APJ.findObservedChannel(ServiceChannels);


            if slotIndex <= obj.ReconnaissanceDuration

                % ===================================================
                % Phase 1 : Reconnaissance
                % ===================================================

                % Target UT의 실제 action 저장
                APJ.Agent.setObservedAction( ...
                    observedChannel);


                % ---------------------------------------------------
                % APJ Shadow DQN Prediction
                % ---------------------------------------------------

                [predictedChannel, apjQValues] = ...
                    APJ.Agent.predictAction();

                APJ.PredictedChannel = ...
                    predictedChannel;


                % ---------------------------------------------------
                % Target UT Greedy Policy
                % ---------------------------------------------------

                [utGreedyChannel, utQValues] = ...
                    UTs(APJ.TargetUTId).Agent.getGreedyAction();



                % ===================================================
                % Shadowing 결과 저장
                % ===================================================

                shadowResult.ActualChannel = ...
                    observedChannel;

                shadowResult.UTGreedyChannel = ...
                    utGreedyChannel;

                shadowResult.APJPredictedChannel = ...
                    predictedChannel;


                % ---------------------------------------------------
                % Actual Action Prediction
                % ---------------------------------------------------

                shadowResult.ActualPredictionCorrect = ...
                    (predictedChannel == observedChannel);


                % ---------------------------------------------------
                % Greedy Policy Agreement
                % ---------------------------------------------------

                shadowResult.GreedyAgreementCorrect = ...
                    (predictedChannel == utGreedyChannel);



                % ===================================================
                % Q-Margin
                %
                % UT Top-1 Q - Top-2 Q
                % ===================================================

                sortedUTQValues = ...
                    sort(utQValues, 'descend');

                qMargin = ...
                    sortedUTQValues(1) - ...
                    sortedUTQValues(2);

                shadowResult.QMargin = ...
                    qMargin;



                % ===================================================
                % Pearson Q-Vector Correlation
                % ===================================================

                utQ = ...
                    double(utQValues(:));

                apjQ = ...
                    double(apjQValues(:));


                if std(utQ) > 0 && std(apjQ) > 0

                    R = ...
                        corrcoef(utQ, apjQ);

                    qCorrelation = ...
                        R(1, 2);

                else

                    qCorrelation = NaN;

                end


                shadowResult.QCorrelation = ...
                    qCorrelation;



                % ===================================================
                % Spearman Rank Correlation
                %
                % Q-value 절대값이 아니라
                % 채널 순위가 얼마나 유사한지 측정
                % ===================================================

                spearmanCorrelation = ...
                    obj.calculateSpearmanCorrelation( ...
                        utQ, ...
                        apjQ);

                shadowResult.SpearmanCorrelation = ...
                    spearmanCorrelation;



                % ===================================================
                % UT Greedy Action의 APJ Rank
                %
                % 예:
                % UT Greedy = Ch 5
                %
                % APJ Ranking:
                % Ch 7 -> Rank 1
                % Ch 5 -> Rank 2
                %
                % => UTGreedyRankInAPJ = 2
                % ===================================================

                [~, apjRanking] = ...
                    sort(apjQ, 'descend');


                utGreedyRankInAPJ = ...
                    find( ...
                        apjRanking == utGreedyChannel, ...
                        1);


                shadowResult.UTGreedyRankInAPJ = ...
                    utGreedyRankInAPJ;



                % ===================================================
                % Top-K Hit
                %
                % rank = 3 이라면
                %
                % Top-1 : false
                % Top-2 : false
                % Top-3 : true
                % Top-4 : true
                % ...
                % ===================================================

                numActions = ...
                    numel(apjQ);


                topKHit = ...
                    (1:numActions) >= utGreedyRankInAPJ;


                shadowResult.TopKHit = ...
                    double(topKHit);



                % ===================================================
                % Debug
                % ===================================================

                if obj.Debug

                    DebugHelper.printAPJShadowing( ...
                        slotIndex, ...
                        observedChannel, ...
                        utGreedyChannel, ...
                        predictedChannel, ...
                        utQValues, ...
                        apjQValues);

                end


            else

                % ===================================================
                % Phase 2 : Attack
                % ===================================================

                % 공격 수행 단계
                % 추후 구현

            end



            %% =======================================================
            % 6. Satellite HARQ
            % ========================================================

            for satelliteIndex = 1:numel(Satellites)

                Satellites(satelliteIndex).performHARQ( ...
                    ServiceChannels, ...
                    ControlChannels, ...
                    UTs);
            end


            % DebugHelper.printChannels( ...
            %     ServiceChannels, ...
            %     ControlChannels);



            %% =======================================================
            % 7. UT / APJ Reward
            % ========================================================

            actualACK = ...
                zeros(1, numel(UTs));


            % ---------------- UT HARQ ----------------

            for utIndex = 1:numel(UTs)

                actualACK(utIndex) = ...
                    UTs(utIndex).receiveHARQFeedback( ...
                        ControlChannels);

            end


            actualTargetACK = ...
                actualACK(APJ.TargetUTId);


            % ---------------- UT Reward ----------------

            if obj.UseAgent

                for utIndex = 1:numel(UTs)

                    UTs(utIndex).Agent.setReward( ...
                        actualACK(utIndex));


                    if obj.Debug && ...
                            utIndex == APJ.TargetUTId

                        DebugHelper.printReward( ...
                            UTs(utIndex).Id, ...
                            UTs(utIndex).Agent.PendingReward, ...
                            actualACK(utIndex));
                    end
                end
            end



            % ---------------- APJ HARQ Estimation ----------------

            estimatedACK = ...
                APJ.estimateHARQ( ...
                    ServiceChannels, ...
                    UTs);


            % ---------------- APJ Reward ----------------

            if slotIndex <= obj.ReconnaissanceDuration

                APJ.Agent.setReward( ...
                    estimatedACK);

            end



            %% =======================================================
            % 결과 반환
            % ========================================================

            if actualTargetACK && estimatedACK

                result = 0;       % TP

            elseif actualTargetACK && ~estimatedACK

                result = 1;       % FN

            elseif ~actualTargetACK && estimatedACK

                result = 2;       % FP

            else

                result = 3;       % TN

            end
        end



        % ============================================================
        % 채널 초기화
        % ============================================================
        function clearChannels(~, ServiceChannels, ControlChannels)

            for channelIndex = 1:numel(ServiceChannels)

                ServiceChannels(channelIndex).clearPacket();

            end


            for channelIndex = 1:numel(ControlChannels)

                ControlChannels(channelIndex).clearPacket();

            end
        end
    end



    methods (Access = private)

        % ============================================================
        % Spearman Rank Correlation 계산
        %
        % 정확히 같은 Q-value tie는 거의 발생하지 않는다는
        % 현재 DQN 환경을 기준으로 함.
        % ============================================================
        function rho = calculateSpearmanCorrelation(~, x, y)

            x = double(x(:));
            y = double(y(:));


            if numel(x) ~= numel(y)

                error( ...
                    "TimeSlot:SpearmanSizeMismatch", ...
                    "두 Q-vector의 크기가 다릅니다.");

            end


            numValues = ...
                numel(x);


            % ---------------- x Rank ----------------

            [~, xOrder] = ...
                sort(x, 'descend');

            xRank = ...
                zeros(numValues, 1);

            xRank(xOrder) = ...
                1:numValues;


            % ---------------- y Rank ----------------

            [~, yOrder] = ...
                sort(y, 'descend');

            yRank = ...
                zeros(numValues, 1);

            yRank(yOrder) = ...
                1:numValues;


            % ---------------- Pearson of Ranks ----------------

            if std(xRank) > 0 && ...
                    std(yRank) > 0

                R = ...
                    corrcoef(xRank, yRank);

                rho = ...
                    R(1, 2);

            else

                rho = NaN;

            end
        end
    end
end