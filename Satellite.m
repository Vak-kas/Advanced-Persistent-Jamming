classdef Satellite < Node
    properties
        NumBeams
        Beams
    end

    methods
        % ========== 생성자 ========== %
        function obj = Satellite(id, position, numBeams)
            obj@Node(id, NodeType.Satellite, position);
            obj.NumBeams = numBeams;

            obj.Beams = Beam.empty(0, numBeams);
        end


         % ========== Beam 추가 ========== %
        function addBeam(obj, beam)
            obj.Beams(end + 1) = beam;
        end

        % ========== Beam 반환 ========== %
        function beam = getBeam(obj, beamId)
            beam = obj.Beams(beamId);
        end


    
        
    end
end