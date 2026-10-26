function [routes, aux] = rlgbka_ops2(id, P, routes, opts)
%RLGBKA_OPS2  Four destroy operators, one per axis of the objective.
%
%   [routes, aux] = rlgbka_ops2(id, P, routes, opts)
%
%   id = 1  merge removal    -- the FLEET axis: try to absorb two routes
%        2  worst removal    -- the DISTANCE axis: remove what costs most
%        3  sector removal   -- the ASSIGNMENT axis: clear a geographic sector
%        4  large ruin       -- the ESCAPE axis: destroy a large part and rebuild
%
%   opts.lam        penalty multipliers (struct with cap, tw)
%   opts.scale      size multiplier, default 1
%
%   WHY THESE FOUR, AND WHY THEY ARE ALL STANDARD
%   Each one targets a different term of the objective, so none is redundant with
%   another and none can be dropped without leaving an axis unaddressed: without
%   merge removal the fleet can only ever grow, because the repair opens a new
%   route whenever nothing fits; without worst removal nothing attacks distance
%   directly; without a spatial destroy no operator rearranges customer-to-route
%   assignment coherently; without a large ruin the search cannot leave the basin
%   it starts in.  All four are known: worst removal and cluster removal are
%   Ropke & Pisinger (2006), large ruin is ruin-and-recreate (Schrimpf et al.
%   2000), and route removal appears in the general heuristic of Ropke & Pisinger
%   (2007).  None of them is a contribution; the point is that the set is
%   complete.
%
%   EVERY OPERATOR IS SAFE.  The repair used here always places every customer,
%   opening a route when nothing fits, so no operator can drop one.  Merge removal
%   compares the resulting fleet with the original and rolls back if it grew, so a
%   failed consolidation costs nothing.

    if nargin < 4, opts = struct(); end
    if ~isfield(opts, 'lam'),   opts.lam = struct('cap', 50, 'tw', 5); end
    if ~isfield(opts, 'scale'), opts.scale = 1; end

    sc = min(max(opts.scale, 0.4), 2.5);
    lam = opts.lam;
    aux = struct('ok', true, 'merged', false, 'removed', 0);

    switch id
        case 1
            [routes, aux] = mergeRemoval(P, routes, lam, sc);
        case 2
            q = randi([max(4, round(6 * sc)), max(5, round(14 * sc))]);
            [routes, rem] = worstRemoval(P, routes, q, lam);
            routes = vrp_repair_greedy(P, routes, rem, lam);
            aux.removed = numel(rem);
        case 3
            q = randi([max(4, round(8 * sc)), max(5, round(18 * sc))]);
            [routes, rem] = sectorRemoval(P, routes, q);
            routes = vrp_repair_greedy(P, routes, rem, lam);
            aux.removed = numel(rem);
        case 4
            q = randi([round(0.20 * P.n * sc), round(0.35 * P.n * sc)]);
            [routes, rem] = randomRemoval(P, routes, q);
            routes = vrp_repair_greedy(P, routes, rem, lam);
            aux.removed = numel(rem);
        case 5
            q = randi([max(4, round(8 * sc)), max(5, round(20 * sc))]);
            [routes, rem] = randomRemoval(P, routes, q);
            routes = vrp_repair_greedy(P, routes, rem, lam);
            aux.removed = numel(rem);
        otherwise
            error('rlgbka_ops2:id', 'unknown operator %d', id);
    end
end


% ---------------------------------------------------------------- operator 1

function [routes, aux] = mergeRemoval(P, routes, lam, sc)
%MERGEREMOVAL  Empty two routes and try to absorb their customers elsewhere.
%
%   This is the only operator that can reduce the fleet.  Every other destroy
%   removes customers and hands them to a repair that opens a new route whenever
%   nothing fits, so the fleet can only grow; measured on R1_2_1, route
%   elimination with ejection chains spent 62 ms per call and never once reduced
%   the fleet, because the surviving routes genuinely had no feasible slot.
%
%   Here the whole set of two routes is offered to the repair at once.  The repair
%   is free to open a route if it must, and the result is rejected unless the fleet
%   actually shrank, so a failed attempt is a no-op rather than damage.
    aux = struct('ok', true, 'merged', false, 'removed', 0);
    nR = numel(routes);
    if nR < 3, return; end

    sizes = cellfun(@numel, routes);
    [~, order] = sort(sizes);
    % bias towards small routes, but keep it random
    pool = order(1:max(2, round(0.4 * nR)));
    pick = pool(randperm(numel(pool), min(2, numel(pool))));
    if numel(pick) < 2, return; end

    r1 = pick(1); r2 = pick(2);
    rem = [routes{r1}(:).', routes{r2}(:).'];
    keep = setdiff(1:nR, [r1 r2]);
    rest = routes(keep);

    cand = vrp_repair_greedy(P, rest, rem, lam);
    if numel(cand) < nR
        routes = cand;
        aux.merged = true;
        aux.removed = numel(rem);
    end
end


% ---------------------------------------------------------------- operator 2

function [routes, rem] = worstRemoval(P, routes, q, lam)
%WORSTREMOVAL  Remove the customers whose presence costs the most.
%
%   The saving of serving c between a and b is D(a,c) + D(c,b) - D(a,b).  A
%   little randomness is mixed in by drawing from the top 2q rather than the top
%   q, which prevents the same set being removed on every visit.
    if isempty(routes), rem = []; return; end
    dep = P.depot;
    S = P.S;

    ids = zeros(0, 1); sav = zeros(0, 1);
    for r = 1:numel(routes)
        rt = routes{r};
        L = numel(rt);
        for k = 1:L
            a = dep; if k > 1, a = rt(k-1); end
            b = dep; if k < L, b = rt(k+1); end
            ids(end+1, 1) = rt(k); %#ok<AGROW>
            sav(end+1, 1) = S.D(a, rt(k)) + S.D(rt(k), b) - S.D(a, b); %#ok<AGROW>
        end
    end

    [~, o] = sort(sav, 'descend');
    q = min(q, numel(o));
    hi = min(numel(o), 2 * q);
    pickPos = randperm(hi, q);
    rem = ids(o(pickPos)).';

    routes = dropCustomers(P, routes, rem);
end


% ---------------------------------------------------------------- operator 3

function [routes, rem] = sectorRemoval(P, routes, q)
%SECTORREMOVAL  Clear a contiguous angular sector around the depot.
%
%   Sweep order is the oldest clustering idea in routing (Gillett & Miller 1974)
%   and is the cheapest form of cluster removal: no seed, no weighted-distance
%   matrix, just a polar sort done once and a contiguous slice.  It removes a set
%   that is geographically coherent by construction, which is what lets the repair
%   reassign whole neighbourhoods between routes.
    if isempty(routes), rem = []; return; end
    ids = zeros(0, 1); ang = zeros(0, 1);
    for r = 1:numel(routes)
        rt = routes{r};
        for k = 1:numel(rt)
            c = rt(k);
            ids(end+1, 1) = c; %#ok<AGROW>
            ang(end+1, 1) = atan2(P.S.y(c) - P.S.y(P.depot), ...
                                 P.S.x(c) - P.S.x(P.depot)); %#ok<AGROW>
        end
    end
    [~, o] = sort(ang);
    n = numel(o);
    q = min(q, n);
    start = randi(n);
    pos = mod((start-1):(start+q-2), n) + 1;
    rem = ids(o(pos)).';

    routes = dropCustomers(P, routes, rem);
end


% ---------------------------------------------------------------- operator 4

function [routes, rem] = randomRemoval(P, routes, q)
    if isempty(routes), rem = []; return; end
    ids = zeros(0, 1);
    for r = 1:numel(routes)
        ids = [ids; routes{r}(:)]; %#ok<AGROW>
    end
    q = min(q, numel(ids));
    rem = ids(randperm(numel(ids), q)).';
    routes = dropCustomers(P, routes, rem);
end


% ---------------------------------------------------------------- shared

function routes = dropCustomers(P, routes, rem) %#ok<INUSD>
%DROPCUSTOMERS  Remove the listed customers from the solution.
    for r = 1:numel(routes)
        if isempty(routes{r}), continue; end
        routes{r} = setdiff(routes{r}, rem, 'stable');
    end
    routes = routes(~cellfun(@isempty, routes));
end
