classdef (Abstract) Node < handle
    properties
        Id
        Type

        Position

        TxGain_dBi
        RxGain_dBi

        k = 1.380649e-23;
    end

    methods
        % ========== 생성자 ==========
        function obj = Node(id, type, position)
            obj.Id = id;
            obj.Type = type;
            obj.Position = position(:);
        end


        % ========== 위치 반환 ==========
        function Position = getPosition(obj)
            Position = obj.Position; % Access the Position property
        end



        % ========== 거리차이 계산 ==========
        function distance = distanceTo(obj, otherNode)
            distance = norm(obj.Position - otherNode.Position);
        end




    end

end