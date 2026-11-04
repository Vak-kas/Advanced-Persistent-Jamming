classdef ChannelModel < handle
    properties
        pathLossExponent
        gainMap
    end
    methods
        %========== 생성자 ==========
        function obj = ChannelModel(pathLossExponent)
            obj.pathLossExponent = pathLossExponent;
            obj.gainMap = containers.Map();
        end
        
        %========== 슬롯 및 채널마다 이득 갱신 [완벽 정합 버전] ==========
        function update(obj, txNodes, rxNodes, jammer, channels)
            obj.gainMap = containers.Map();
            N = length(txNodes);
            K = length(channels);
            
            % 1. 모든 노드(Tx_i, Rx_j) 간의 정방향 데이터 간섭 링크 및 역방향 ACK 간섭 링크를 완벽히 매핑
            for txIdx = 1:N
                for rxIdx = 1:N
                    txNode = txNodes{txIdx};
                    rxNode = rxNodes{rxIdx};
                    
                    % 물리적 직선 거리 계산 (유저님 기존 논문 좌표 구조 100% 유지)
                    distance = norm(txNode.position - rxNode.position);
                    distance = max(distance, 1);
                    largeScaleFading = distance^(-obj.pathLossExponent);
                    
                    for k = 1:K
                        h = (randn + 1i * randn) / sqrt(2);
                        % smallScaleFading = abs(h)^2;
                        smallScaleFading = 1;
                        gain = largeScaleFading * smallScaleFading;
                        
                        % [정방향 데이터 링크 키] Tx_i -> Rx_j
                        keyData = obj.makeKey(txNode.role, txNode.id, rxNode.role, rxNode.id, k);
                        obj.gainMap(keyData) = gain;
                        
                        % [★ 버그 수정 - 역방향 ACK 링크 키] Rx_j -> Tx_i 
                        % 무선 채널 대칭성(Reciprocity)에 의해 동일 주파수 대역의 gain 값을 
                        % 역방향 수신 노드 역할 구조에 맞춰 한 치의 빈틈도 없이 완벽하게 상호 매핑합니다.
                        keyReverse = obj.makeKey(rxNode.role, rxNode.id, txNode.role, txNode.id, k);
                        obj.gainMap(keyReverse) = gain;
                    end
                end
            end
            
            % 2. Jammer -> Tx/Rx 사용자 링크 (유저님 기존 정석 로직 유지)
            for n = 1:N
                txNode = txNodes{n};
                rxNode = rxNodes{n};
                
                dTx = max(norm(jammer.position - txNode.position), 1);
                largeTx = dTx^(-obj.pathLossExponent);
                
                dRx = max(norm(jammer.position - rxNode.position), 1);
                largeRx = dRx^(-obj.pathLossExponent);
                
                for k = 1:K
                    hTx = (randn + 1i * randn) / sqrt(2);
                    hRx = (randn + 1i * randn) / sqrt(2);
                    
                    keyJammerToTx = obj.makeKey(jammer.role, jammer.id, txNode.role, txNode.id, k);
                    obj.gainMap(keyJammerToTx) = largeTx * abs(hTx)^2;
                    
                    keyJammerToRx = obj.makeKey(jammer.role, jammer.id, rxNode.role, rxNode.id, k);
                    obj.gainMap(keyJammerToRx) = largeRx * abs(hRx)^2;
                end
            end
        end
        
        %========== 채널 이득 가져오기 ==========
        % [수정] 채널 ID(k)를 인자로 받아 해당 주파수의 정확한 gain을 반환합니다.
        function gain = getGain(obj, txRole, txId, rxRole, rxId, channelId)
            key = obj.makeKey(txRole, txId, rxRole, rxId, channelId);
            if isKey(obj.gainMap, key)
                gain = obj.gainMap(key);
            else
                gain = 0;
            end
        end
        
        %========== 링크 key 생성 (채널 ID 포함) ==========
        function key = makeKey(obj, txRole, txId, rxRole, rxId, channelId)
            key = sprintf("%s%d_%s%d_CH%d", ...
                string(txRole), txId, ...
                string(rxRole), rxId, channelId);
        end
    end
end