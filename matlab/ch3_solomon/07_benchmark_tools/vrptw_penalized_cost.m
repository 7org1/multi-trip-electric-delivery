function [f, viol, R] = vrptw_penalized_cost(S, routes, lam)
%VRPTW_PENALIZED_COST  Distance plus weighted constraint violation.
%
%   [f, viol, R] = vrptw_penalized_cost(S, routes, lam)
%
%   lam    struct with .cap and .tw penalty coefficients
%
%   f      dist + lam.cap * totalCapacityExcess + lam.tw * totalTimeWindowExcess
%   viol   total scaled violation (what the adaptive lambda reacts to)
%   R      .dist .nveh .capExcess .twExcess .feasible
%
% WHY A PENALTY RATHER THAN INFINITY
%   At a fixed fleet size equal to the best-known vehicle count, a strictly
%   feasible search is trapped: the constructive solution uses one route too
%   many and no single feasible move reaches a better basin.  Charging the
%   amount of violation lets the search cross infeasible ground and come back
%   feasible, which is the standard treatment in tabu search for the VRPTW
%   (Bräysy 2003) and is built into HGS (Vidal 2022).
%
%   The returned solution is only ACCEPTED when it is feasible; the penalty is
%   a search device, not a way of reporting an infeasible answer.

    if nargin < 3 || isempty(lam)
        lam = struct('cap', 1e3, 'tw', 1e3);
    end

    dist = 0; capX = 0; twX = 0; nveh = 0;
    for r = 1:numel(routes)
        if isempty(routes{r}), continue; end
        st = vrptw_route_stats(S, routes{r});
        dist = dist + st.dist;
        capX = capX + st.capExcess;
        twX  = twX  + st.twExcess;
        nveh = nveh + 1;
    end

    % exceeding the fleet limit is also a violation
    fleetX = max(0, nveh - S.m);

    viol = lam.cap * (capX + 100 * fleetX) + lam.tw * twX;
    f    = dist + viol;

    R.dist      = dist;
    R.nveh      = nveh;
    R.capExcess = capX;
    R.twExcess  = twX;
    R.fleetExcess = fleetX;
    R.feasible  = (capX <= 1e-9) && (twX <= 1e-9) && (fleetX == 0);
end
