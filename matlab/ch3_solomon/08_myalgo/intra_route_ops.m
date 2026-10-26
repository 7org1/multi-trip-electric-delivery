function [routes, aux] = intra_route_ops(P, routes, lam, sc)
%INTRA_ROUTE_OPS  Reorder customers inside each route: 2-opt plus or-opt.
%
%   NOT YET WIRED INTO rlgbka_ops.  This file exists to measure the cost of the
%   mechanism before deciding whether it replaces the elite-relinking operator,
%   which currently duplicates what the light kick already does.
%
%   WHAT IT CHANGES, AND WHY THAT IS A DISTINCT ROLE
%   None of the other three operators reorders customers *within* a route.  Route
%   elimination changes the fleet, the light kick changes which route a customer
%   belongs to, and the string move relocates a block while preserving its
%   internal order.  The order inside a route is currently never optimised, so a
%   route can be internally taut while every cross-route operator reports no
%   improvement.  On the tight-window instances that is precisely the state the
%   search sits in.
%
%   TWO-STAGE FILTERING, FOR THE SAME REASON AS repairPenalized
%   A route of length L has L^2/2 two-opt candidates and 3L^2 or-opt candidates --
%   about 350 for L = 10, so 7,700 full route evaluations over 22 routes, roughly
%   400 ms.  The distance change of both move types is O(1) from the distance
%   matrix, so candidates are ranked on that and only the best KEEP are scored
%   exactly.  Ranking on distance alone can in principle miss a move that is
%   worse in distance but better once violations are penalised; KEEP is set to 5
%   to keep that risk small.

    aux = struct('repaired', false, 'eliminated', false, 'removed', 0);

    KEEP = 5;
    dep = P.depot;
    S = P.S;

    for r = 1:numel(routes)
        rt = routes{r};
        L = numel(rt);
        if L < 3, continue; end

        base = routePenOf(P, rt, lam);
        if base < 0, continue; end

        candList = cell(0, 1);
        dList = zeros(0, 1);

        % ---- 2-opt: reverse the segment rt(i..j)
        for i = 1:L-1
            for j = i+1:L
                a = dep; if i > 1, a = rt(i-1); end
                b = rt(i);
                c = rt(j);
                d = dep; if j < L, d = rt(j+1); end
                delta = S.D(a, c) + S.D(b, d) - S.D(a, b) - S.D(c, d);
                mv = [rt(1:i-1), rt(j:-1:i), rt(j+1:end)];
                [dList, candList] = keepBest(dList, candList, delta, mv, KEEP);
            end
        end

        % ---- or-opt: move a segment of length 1..3 elsewhere in the same route
        for len = 1:min(3, L-1)
            for i = 1:L-len+1
                seg = rt(i:i+len-1);
                rest = rt([1:i-1, i+len:end]);
                for p = 0:numel(rest)
                    if p == i-1, continue; end          % unchanged position
                    a = dep; if p > 0, a = rest(p); end
                    b = dep; if p < numel(rest), b = rest(p+1); end
                    delta = S.D(a, seg(1)) + S.D(seg(end), b) - S.D(a, b);
                    mv = [rest(1:p), seg, rest(p+1:end)];
                    [dList, candList] = keepBest(dList, candList, delta, mv, KEEP);
                end
            end
        end

        bestC = base; bestRt = rt;
        for k = 1:numel(candList)
            c = routePenOf(P, candList{k}, lam);
            if c < bestC - 1e-9
                bestC = c; bestRt = candList{k};
            end
        end

        if bestC < base - 1e-9
            routes{r} = bestRt;
            aux.repaired = true;
        end
    end
end


function [dList, candList, added] = keepBest(dList, candList, d, mv, KEEP)
%KEEPBEST  Maintain the KEEP cheapest candidates seen so far.
    added = false;
    if numel(dList) < KEEP
        dList(end+1, 1) = d; candList{end+1, 1} = mv;
        [dList, o] = sort(dList); candList = candList(o);
        added = true;
    elseif d < dList(end)
        dList(end) = d; candList{end} = mv;
        [dList, o] = sort(dList); candList = candList(o);
        added = true;
    end
end


function rp = routePenOf(P, rt, lam)
    if isempty(rt), rp = 0; return; end
    st = P.stats(rt);
    rp = st.dist + lam.cap * st.capExcess + lam.tw * st.twExcess;
end
