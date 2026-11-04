classdef Experience

    properties
        O_t
        action

        r_u
        r_j

        O_next
    end

    methods

        function obj = Experience(O_t, action, r_u, r_j, O_next)

            obj.O_t = O_t;
            obj.action = action;

            obj.r_u = r_u;
            obj.r_j = r_j;

            obj.O_next = O_next;

        end

    end

end