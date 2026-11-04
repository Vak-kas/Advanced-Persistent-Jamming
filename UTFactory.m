classdef UTFactory
    methods (Static)

        % ========== UT 전체 생성 ==========
        function UTs = createUTs(Beams, numUTs)

            UTs = UT.empty(0, numUTs);
            for utIndex = 1:numUTs
                beam = Beams(utIndex);
                utPosition = UTFactory.generateUTPosition(beam); % 해당 Beam 내부에서 UT 위치 생성
                UTs(utIndex) = UT(utIndex, utPosition);

            end
        end


        % ========== Beam 내부 UT 위치 생성 ==========
        function position = generateUTPosition(beam)

            % Beam 원 내부 균일 랜덤 배치
            randomRadius = sqrt(rand()) * beam.Radius;
            randomAngle = 2 * pi * rand();

            % x = beam.CenterPosition(1) + randomRadius * cos(randomAngle);
            % y = beam.CenterPosition(2) + randomRadius * sin(randomAngle);
            x = beam.CenterPosition(1);
            y = beam.CenterPosition(2);
            z = 0;
            position = [x y z];

        end

    end
end