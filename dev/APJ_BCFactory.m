classdef APJ_BCFactory
    methods (Static)

        % ========== APJ 생성 ==========
        function APJNode = createAPJ_BC(UTs, Beams, targetUTId, targetJammerDistance)

            targetUT = UTs(targetUTId);
            targetPosition = targetUT.getPosition();

            targetBeam = Beams(targetUT.AssociatedBeamId);

            % APJ 위치 생성
            apjPosition = APJFactory.generateAPJPosition(targetPosition, targetBeam, targetJammerDistance );

            % APJ 객체 생성
            APJNode = APJ_BC(1001, apjPosition, targetUTId );

        end


        % ========== APJ 위치 생성 ==========
        function position = generateAPJPosition(targetPosition, targetBeam, targetJammerDistance)

            maxPlacementAttempts = 10000;

            isPlaced = false;
            attemptCount = 0;

            while ~isPlaced

                attemptCount = attemptCount + 1;

                if attemptCount > maxPlacementAttempts
                    error( ...
                        "APJ_BCFactory:PlacementFailed", ...
                        "Target UT로부터 %.2f km 거리이면서 Beam %d 내부인 APJ 위치를 찾지 못했습니다.", ...
                        targetJammerDistance / 1e3, ...
                        targetBeam.Id ...
                    );
                end


                % Target UT 기준 랜덤 방향
                randomAngle = 2 * pi * rand();

                x = targetPosition(1) ...
                    + targetJammerDistance * cos(randomAngle);

                y = targetPosition(2) ...
                    + targetJammerDistance * sin(randomAngle);

                z = 0;

                candidatePosition = [x y z];


                % Target Beam 내부인지 검사
                distanceToBeamCenter = ...
                    targetBeam.groundDistanceTo(candidatePosition);

                if distanceToBeamCenter <= targetBeam.Radius
                    isPlaced = true;
                end

            end

            position = candidatePosition;

        end
       

    end
end