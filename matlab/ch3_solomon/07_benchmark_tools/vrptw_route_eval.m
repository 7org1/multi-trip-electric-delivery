function [ok, dist, tEnd, load, tStart] = vrptw_route_eval(S, route, tDepart)
%VRPTW_ROUTE_EVAL  Feasibility, distance and finish time of one route.
%
%   [ok, dist, tEnd, load, tStart] = vrptw_route_eval(S, route)
%   [...] = vrptw_route_eval(S, route, tDepart)
%
%   route    customer indices (2..N); the depot is implicit at both ends.
%            An empty route is feasible with zero cost.
%   tDepart  departure time from the depot, default 0
%
%   ok       true when capacity AND every time window are satisfied
%   dist     total distance of the complete route
%   tEnd     time of arrival back at the depot
%   load     total demand on the route
%   tStart   service-start time at each stop
%
% DISTANCE AND LOAD ARE ALWAYS COMPLETE
%   An earlier version returned early when a due date was violated, so `dist`
%   covered only the prefix of the route.  That is a silent trap: every caller
%   that used the distance of an infeasible route as a penalty or as a
%   diagnostic got a number that was too small, and the bias grew with how
%   deeply the route was infeasible.  Distance and load are geometric
%   properties of the route and do not depend on feasibility, so they are now
%   always accumulated to the end; only `ok` records the violation.
%
% CONVENTION
%   `ready`/`due` bound the START of service, not the arrival.  Waiting is free
%   (the benchmark objective is distance only).

    if nargin < 3 || isempty(tDepart), tDepart = 0; end

    if isempty(route)
        ok = true; dist = 0; tEnd = tDepart; load = 0; tStart = [];
        return;
    end

    dep = S.depot;
    L   = numel(route);

    dist = 0;
    load = 0;
    t    = tDepart;
    ok   = true;
    tStart = zeros(L, 1);
    prev = dep;

    for k = 1:L
        c = route(k);
        dist = dist + S.D(prev, c);
        load = load + S.demand(c);

        if ok
            t = t + S.T(prev, c);
            if t < S.ready(c), t = S.ready(c); end
            tStart(k) = t;
            if t > S.due(c) + 1e-9
                ok = false;          % keep going: timing is no longer used
            else
                t = t + S.service(c);
            end
        end
        prev = c;
    end

    dist = dist + S.D(prev, dep);

    if ok
        tEnd = t + S.T(prev, dep);
        if tEnd > S.due(dep) + 1e-9
            ok = false;
        end
    else
        tEnd = NaN;
    end

    if load > S.Q + 1e-9
        ok = false;
    end
end
