function st = vrptw_route_stats(S, route)
%VRPTW_ROUTE_STATS  Distance, load, and VIOLATION MAGNITUDES of one route.
%
%   st = vrptw_route_stats(S, route)
%
%   st.dist       total distance
%   st.load       total demand
%   st.capExcess  max(0, load - Q)
%   st.twExcess   sum of max(0, serviceStart - due), in time units
%   st.tEnd       arrival back at the depot (NaN if a window was violated)
%   st.feasible   true when both excesses are zero
%
% WHY VIOLATION MAGNITUDES AND NOT A BOOLEAN
%   Comparisons at a fixed fleet size require the search to pass through
%   infeasible states: reaching the best-known solution with a tight fleet
%   almost never happens along an all-feasible path.  A boolean flag cannot
%   guide such a search, so the amount of violation is accumulated and charged
%   through a penalty term.
%
%   The public evaluation used for reporting, vrptw_route_eval, keeps its
%   early-exit-free behaviour and remains the authority on feasibility.

    dep = S.depot;
    L   = numel(route);

    if L == 0
        st = struct('dist', 0, 'load', 0, 'capExcess', 0, 'twExcess', 0, ...
                    'tEnd', 0, 'feasible', true);
        return;
    end

    dist = 0; load = 0; tw = 0;
    t = 0; prev = dep;

    for k = 1:L
        c = route(k);
        dist = dist + S.D(prev, c);
        load = load + S.demand(c);
        t = t + S.T(prev, c);
        if t < S.ready(c), t = S.ready(c); end
        late = t - S.due(c);
        if late > 0
            tw = tw + late;
            % service still has to happen; keep timing monotone
        end
        t = t + S.service(c);
        prev = c;
    end

    dist = dist + S.D(prev, dep);
    tEnd = t + S.T(prev, dep);
    tw = tw + max(0, tEnd - S.due(dep));

    st = struct();
    st.dist      = dist;
    st.load      = load;
    st.capExcess = max(0, load - S.Q);
    st.twExcess  = tw;
    st.tEnd      = tEnd;
    st.feasible  = (st.capExcess <= 1e-9) && (tw <= 1e-9);
end
