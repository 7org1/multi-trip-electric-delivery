function [bestR, bestP, bestDelta, found, perRoute] = vrptw_insert_best(S, routes, j, allowNewRoute)
%VRPTW_INSERT_BEST  Cheapest FEASIBLE insertion of customer j, in O(n) per call.
%
%   [bestR, bestP, bestDelta, found] = vrptw_insert_best(S, routes, j)
%   [...] = vrptw_insert_best(S, routes, j, allowNewRoute)
%
%   bestR      route index; numel(routes)+1 means "open a new route"
%   bestP      position inside that route (1..len+1)
%   bestDelta  increase in total distance
%   found      false when j fits nowhere and a new route is not allowed
%   perRoute   [numel(routes) x 2] best (delta, pos) per route, NaN if none
%
% HOW THE O(1) FEASIBILITY TEST WORKS
%   For each route two arrays are computed once, in O(len):
%
%     tS(k)      earliest feasible service start at position k (forward pass)
%     latest(k)  latest service start that still satisfies k..end (backward):
%                  latest(end) = due(end)
%                  latest(k)   = min(due(k), latest(k+1) - service(k) - T(k,k+1))
%
%   Waiting is free, and arriving later is never better than arriving early and
%   waiting, so `latest` is exact rather than merely a bound.
%
%   Inserting j before position p only ever changes the entry time of position
%   p, so the whole route stays feasible iff
%
%       max(tJ + service(j) + T(j, rt(p)), ready(rt(p))) <= latest(p)
%
%   That is one comparison per candidate position.  The previous version
%   propagated the delay through every following node, which is O(len) per
%   position and made ALNS ~10x too slow to be usable at 200 customers.
%
% FEASIBILITY IS EXACT
%   Capacity and every time window are checked, so a returned insertion never
%   makes a route infeasible.

    if nargin < 4, allowNewRoute = true; end

    dep  = S.depot;
    demJ = S.demand(j);
    srvJ = S.service(j);
    rdyJ = S.ready(j);
    dueJ = S.due(j);
    dueDepot = S.due(dep);

    nR = numel(routes);
    perRoute = nan(nR, 2);

    bestDelta = inf; bestR = 0; bestP = 0; found = false;

    for r = 1:nR
        rt = routes{r};
        L  = numel(rt);
        rBest = inf; rBestP = 0;

        if isempty(rt)
            if demJ <= S.Q + 1e-9 && rdyJ <= dueJ + 1e-9
                d = S.D(dep, j) + S.D(j, dep);
                if rdyJ > S.T(dep, j), tArr = rdyJ; else, tArr = S.T(dep, j); end
                if tArr + srvJ + S.T(j, dep) <= dueDepot + 1e-9
                    rBest = d; rBestP = 1;
                end
            end
        else
            loadR = 0;
            for c = rt, loadR = loadR + S.demand(c); end
            if loadR + demJ <= S.Q + 1e-9
                % ---- forward pass: earliest service starts
                tS = zeros(L, 1);
                t  = 0; pn = dep;
                for k = 1:L
                    c = rt(k);
                    t = t + S.T(pn, c);
                    if t < S.ready(c), t = S.ready(c); end
                    tS(k) = t;
                    t = t + S.service(c);
                    pn = c;
                end

                % ---- backward pass: latest tolerable service starts
                latest = zeros(L, 1);
                latest(L) = S.due(rt(L));
                for k = L-1:-1:1
                    c = rt(k); nx = rt(k+1);
                    lb = latest(k+1) - S.service(c) - S.T(c, nx);
                    latest(k) = min(S.due(c), lb);
                end

                % ---- one comparison per insertion point
                for p = 1:L+1
                    if p == 1
                        pn = dep; tDone = 0;
                    else
                        pn = rt(p-1); tDone = tS(p-1) + S.service(pn);
                    end
                    if p <= L, nxt = rt(p); else, nxt = dep; end

                    d = S.D(pn, j) + S.D(j, nxt) - S.D(pn, nxt);
                    if d >= rBest, continue; end

                    tJ = tDone + S.T(pn, j);
                    if tJ < rdyJ, tJ = rdyJ; end
                    if tJ > dueJ + 1e-9, continue; end

                    tArrNext = tJ + srvJ + S.T(j, nxt);
                    if p <= L
                        newStart = max(tArrNext, S.ready(nxt));
                        if newStart > latest(p) + 1e-9, continue; end
                    else
                        if tArrNext > dueDepot + 1e-9, continue; end
                    end

                    rBest = d; rBestP = p;
                end
            end
        end

        perRoute(r, 1) = rBest;
        perRoute(r, 2) = rBestP;
        if rBest < bestDelta
            bestDelta = rBest; bestR = r; bestP = rBestP; found = true;
        end
    end

    if allowNewRoute && nR < S.m
        if demJ <= S.Q + 1e-9 && rdyJ <= dueJ + 1e-9
            d = S.D(dep, j) + S.D(j, dep);
            tJ = max(S.T(dep, j), rdyJ);
            if tJ <= dueJ + 1e-9 && tJ + srvJ + S.T(j, dep) <= dueDepot + 1e-9
                if d < bestDelta || ~found
                    bestDelta = d; bestR = nR + 1; bestP = 1; found = true;
                end
            end
        end
    end
end
