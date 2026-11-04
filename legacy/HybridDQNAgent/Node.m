classdef Node < handle

    properties
        id

        role          % Tx, Rx, Jammer
        position      % [x, y, z]
        txPower       % mW

        currentChannel
        FHP

        txBuffer
        rxBuffer



        Tc_ms
        Ttrans_ms
        Tack_ms
        Tdec_ms
    end

    methods
        %========== 노드 초기화 ==========
        function obj = Node(id, role, position, txPower, FHP, Tc_ms)
            obj.id = id;
            obj.role = role;
            obj.position = position;
            obj.txPower = txPower;
            obj.FHP = FHP;
            obj.Tc_ms = Tc_ms;

            obj.currentChannel = [];
            obj.txBuffer = {};
            obj.rxBuffer = {};


            % 7 : 2 : 1 비율
            obj.Ttrans_ms = Tc_ms * 0.7;
            obj.Tack_ms  = Tc_ms * 0.2;
            obj.Tdec_ms  = Tc_ms * 0.1;
        end

        %========== 채널 선택 ==========
        function ch = selectChannel(obj, slot, channels)
            N = length(channels);
            channelId = obj.FHP(slot, N);
            obj.currentChannel = channels{channelId};
            ch = obj.currentChannel;
        end

        %========== 채널 ID로 직접 설정 ==========
        function ch = setChannelById(obj, channelId, channels)
            K = length(channels);
            if channelId < 1 || channelId > K
                error("Invalid channelId: %d", channelId);
            end
            obj.currentChannel = channels{channelId};
            ch = obj.currentChannel;
        
        end

        %========== 데이터 패킷 생성 ==========
        function createDataPacket(obj, dstId, payload)
            pkt = Packet(PacketType.DATA, obj.id, dstId, payload);
            obj.txBuffer{end+1} = pkt;
        end

        %========== 송신 버퍼에서 패킷 꺼내기 ==========
        function pkt = popTxPacket(obj)
            if isempty(obj.txBuffer)
                pkt = [];
                return;
            end

            pkt = obj.txBuffer{1};
            obj.txBuffer(1) = [];
        end

        %========== 패킷 송신 ==========
        function pkt = sendPacket(obj)
            pkt = obj.popTxPacket();
        
            if isempty(pkt)
                return;
            end
        
            if isempty(obj.currentChannel)
                error("currentChannel is empty. Select channel first.");
            end
        
            % Packet type에 따라 slot 내부 상대 시간 설정
            if pkt.type == PacketType.DATA
                startTime_ms = 0;
                endTime_ms   = obj.Ttrans_ms;
        
            elseif pkt.type == PacketType.ACK || pkt.type == PacketType.NACK
                startTime_ms = obj.Ttrans_ms;
                endTime_ms   = obj.Ttrans_ms + obj.Tack_ms;
        
            else
                startTime_ms = 0;
                endTime_ms   = obj.Tc_ms;
        
            end
        
            sig = Signal( ...
                SignalType.COMM, ...
                pkt, ...
                obj.txPower, ...
                obj.id, ...
                obj.role, ...
                obj.currentChannel.id, ...
                obj.position, ...
                startTime_ms, ...
                endTime_ms ...
            );
        
            obj.currentChannel.addSignal(sig);
        
        end

        %========== 패킷 수신(DATA 수신 후 ACK/NACK 생성) ==========
        function pkt = receivedPacket(obj, channels, betaThreshold, thermalNoise, channelModel)
            pkt = [];

            for i = 1:length(channels)
                channel = channels{i};
                signals = channel.getSignals();

                if isempty(signals)
                    continue;
                end

                for j = 1:length(signals)
                    sig = signals{j};

                    if sig.type ~= SignalType.COMM
                        continue;
                    end

                    if isempty(sig.packet)
                        continue;
                    end

                    if sig.packet.dstId ~= obj.id
                        continue;
                    end

                    pkt = sig.packet;

                    if pkt.type ~= PacketType.DATA
                        continue;
                    end

                    sinr = obj.computeSINR(channel, sig, thermalNoise, channelModel);

                    % Node.m 내부 receivedPacket 메서드 수정
                    if sinr > betaThreshold
                        obj.rxBuffer{end+1} = pkt;
                        ackPkt = Packet(PacketType.ACK, obj.id, pkt.srcId, "ACK");
                        obj.txBuffer{end+1} = ackPkt;
                        obj.currentChannel = channel; % ACK 송신 채널 확정
                    else
                        nackPkt = Packet(PacketType.NACK, obj.id, pkt.srcId, "NACK");
                        obj.txBuffer{end+1} = nackPkt;
                        obj.currentChannel = channel; % ★ [수정] NACK도 데이터가 날아왔던 이 채널로 정확하게 회신하도록 설정!
                    end

                    return;
                end
            end
        end

        %========== 패킷 수신(ACK/NAC) ==========
        % Node.m 내부 receiveAck 메서드 수정
        function success = receiveAck(obj, betaThreshold, thermalNoise, channelModel)
            success = false;
            if isempty(obj.currentChannel), return; end
            
            signals = obj.currentChannel.getSignals();
            if isempty(signals), return; end
            
            for i = 1:length(signals)
                sig = signals{i};
                if sig.type ~= SignalType.COMM, continue; end
                if isempty(sig.packet), continue; end
                
                pkt = sig.packet;
                if pkt.dstId ~= obj.id, continue; end
                
                % 1. [★ 철벽 수비] NACK 타입 패킷이 내 주파수 축에서 발견되었다? 
                % SINR이 무한대든 나발이든 간에 수신기가 못 받았다고 선언한 것이므로 즉시 실패 처리!
                if pkt.type == PacketType.NACK
                    obj.rxBuffer{end+1} = pkt;
                    success = false; % 무조건 실패
                    % fprintf("Tx %d | Received 명시적 NACK -> 통신 실패\n", obj.id);
                    return;
                end
                
                % 2. ACK 타입 패킷일 때만 정상적으로 무선 SINR 통과 장벽을 평가합니다.
                if pkt.type == PacketType.ACK
                    ackSinr = obj.computeSINR(obj.currentChannel, sig, thermalNoise, channelModel);
                    % 다음과 같이 출력문을 살짝 다듬으면 나중에 화면 보기 아주 편해집니다.
                    if ackSinr > betaThreshold
                        obj.rxBuffer{end+1} = pkt;
                        success = true;
                        % fprintf("Tx %d | ACK 수신 성공 (SINR = %.3e)\n", obj.id, ackSinr);
                    else
                        success = false;
                        % fprintf("Tx %d | ACK 수신 실패 - 신호 깨짐 (SINR = %.3e)\n", obj.id, ackSinr);
                    end

                    return;
                end
            end
        end

        %========== SINR 계산 ==========
        function sinr = computeSINR(obj, channel, desiredSignal, thermalNoise, channelModel)
            desiredPower = obj.computeReceivedPower(desiredSignal, channelModel);

            jammingPower = 0;
            interferencePower = 0;


            desiredDuration = desiredSignal.getDuration();

            if desiredDuration <= 0 || isinf(desiredDuration)
                desiredDuration = 1;
            end

            signals = channel.getSignals();

            for i = 1:length(signals)
                sig = signals{i};

                if obj.isSameSignal(sig, desiredSignal)
                    continue;
                end

                overlapTime = desiredSignal.getOverlapTime(sig);

                if overlapTime <= 0
                    continue;
                end

                rho = overlapTime / desiredDuration;
                if sig.type == SignalType.JAMMING
                    % fprintf( ...
                    %     "  JAM CH%d | overlap=%.2f ms | rho=%.2f\n", ...
                    %     sig.txChannelId, overlapTime, rho);
                end
                

                rxPower = obj.computeReceivedPower(sig, channelModel) * rho;


                if sig.type == SignalType.JAMMING
                    jammingPower = jammingPower + rxPower;
                elseif sig.type == SignalType.COMM
                    interferencePower = interferencePower + rxPower;
                end
            end

            sinr = desiredPower / (jammingPower + interferencePower + thermalNoise);

            % fprintf("Node %d | CH %d | desired=%.3e | jam=%.3e | interf=%.3e | noise=%.3e | SINR=%.3e\n", ...
            %     obj.id, channel.id, desiredPower, jammingPower, interferencePower, thermalNoise, sinr);
        end

        %========== 수신 전력 계산 ==========
        function rxPower = computeReceivedPower(obj, sig, channelModel)
            % sig 객체가 들고 있는 현재 주파수 채널 ID(txChannelId)를 함께 넘겨줍니다.
            gain = channelModel.getGain( ...
                sig.txRole, ...
                sig.txNodeId, ...
                obj.role, ...
                obj.id, ...
                sig.txChannelId ...   % <-- 채널 ID 인자 추가!
            );
            rxPower = sig.txPower * gain;
        end

        %========== 동일 Signal 여부 확인 ==========
        function same = isSameSignal(obj, sig1, sig2)
            same = false;

            if sig1.type ~= sig2.type
                return;
            end

            if sig1.txNodeId ~= sig2.txNodeId
                return;
            end

            if sig1.txChannelId ~= sig2.txChannelId
                return;
            end

            if sig1.txRole ~= sig2.txRole
                return;
            end

            if isempty(sig1.packet) && isempty(sig2.packet)
                same = true;
                return;
            end

            if isempty(sig1.packet) || isempty(sig2.packet)
                return;
            end

            same = sig1.packet.srcId == sig2.packet.srcId && ...
                   sig1.packet.dstId == sig2.packet.dstId && ...
                   sig1.packet.type == sig2.packet.type;
        end



    end
end