function [routes, aux] = rlgbka_ops(id, P, routes, ctx)
%RLGBKA_OPS  The eight discrete operators of RL-GBKA.
%
%   [routes, aux] = rlgbka_ops(id, P, routes, ctx)
%
%   id      1..8, see the table below
%   P       problem adapter (see problem_static)
%   routes  current solution, cell array of customer-index vectors
%   ctx     .lam  .ctr  .elite (cell array)  .vehWeight
%
%   aux.repaired   whether a repair step was applied
%   aux.eliminated true when operator 4 removed a whole route successfully
%
% THE EIGHT OPERATORS
%   1  far removal          remove customers far from the depot (diversity)
%   2  related removal      Shaw removal around a random seed customer
%   3  large random removal remove 30-50% of all customers (escape)
%   4  ROUTE ELIMINATION    try to empty the smallest route (cuts fleet size)
%   5  worst removal        remove the customers whose removal saves most
%   6  greedy repair        cheapest feasible insertion, one at a time
%   7  regret-2 repair      insert the customer that would hurt most to defer
%   8  elite path relinking move the solution toward an elite solution
%
% OPERATORS 1-5 ARE DESTROY OPERATORS AND ARE FOLLOWED BY A REPAIR.
%   6 and 7 can be selected on their own: they then repair the current solution
%   after a light random removal, which is how GBKA's "local refinement"
%   strategy (originally the golden-sine step) is expressed in discrete space.
%
% OPERATOR 4 IS THE ONE THE FOUR BASELINES DO NOT HAVE
%   Single-customer moves cannot empty a route unless it holds one customer, so
%   relocate / exchange / 2-opt* cannot reduce the fleet.  Route elimination is
%   what makes the best-known vehicle count reachable at all.

    if nargin < 4, ctx = struct(); end
    ctx = setdef(ctx, 'lam', struct('cap', 50, 'tw', 5));
    ctx = setdef(ctx, 'ctr', ffe_budget(inf));
    ctx = setdef(ctx, 'elite', {});
    ctx = setdef(ctx, 'scale', 1);
    ctx = setdef(ctx, 'vehWeight', 0);

    lam = ctx.lam;
    ctr = ctx.ctr;
    % Operator scale, chosen by the policy.  This is what couples the operator to
    % the learning: the same operator with a different scale is a different move,
    % and only the policy decides which.  Clamped so a greedy scale choice cannot
    % make an operator degenerate.
    sc = ctx.scale;
    if isempty(sc) || ~isfinite(sc), sc = 1; end
    sc = min(max(sc, 0.4), 2.5);

    aux = struct('repaired', false, 'eliminated', false, 'removed', 0);

    switch id
        case 1
            q = randi([max(2, round(0.02 * P.n)), max(3, round(0.06 * P.n))]);
            [routes, rem] = destroyFar(P, routes, q);
            [routes, ok] = repairGreedy(P, routes, rem, lam, ctr);
            aux.repaired = ok;
        case 2
            q = randi([max(2, round(0.02 * P.n)), max(3, round(0.08 * P.n))]);
            [routes, rem] = destroyRelated(P, routes, q);
            [routes, ok] = repairRegret(P, routes, rem, lam, ctr, 2);
            aux.repaired = ok;
        case 3
            q = randi([max(4, round(0.05 * P.n)), max(5, round(0.12 * P.n))]);
            [routes, rem] = destroyRandom(P, routes, q);
            [routes, ok] = repairGreedy(P, routes, rem, lam, ctr);
            aux.repaired = ok;
        case 4
            % A FAILED ELIMINATION MUST RETURN THE ORIGINAL SOLUTION.
            % destroyRoute removes the route before the reinsertion runs, and
            % repairEjection moves some customers out of it before it can discover
            % that the rest have nowhere to go.  Keeping either partial result
            % drops customers: with a round-robin schedule this produced solutions
            % serving 12 of 200 customers and reporting "1 vehicle, distance 318",
            % which reads as a 93% improvement over the best known solution and is
            % pure artefact.  snapshot is taken before the route is removed, and a
            % failed elimination restores it, so the move becomes a no-op.
            snapshot = routes;
            [routes, ~, rem] = destroyRoute(P, routes, lam);
            if ~isempty(rem)
            % EJECTION-CHAIN REINSERTION, not penalty-based.  A route can only be
            % emptied if its customers go elsewhere, and every feasible position is
            % already full -- that is exactly why the four baselines are stuck one
            % vehicle above the best known.  Allowing the reinsertion to violate a
            % time window and letting the penalty repair it afterwards was the
            % original design, but it became useless once the acceptance rule was
            % corrected to reject every infeasible candidate: measured at 1,718
            % calls and zero improvements.  Ejecting keeps the move feasible
            % throughout and does reduce the fleet.
                [routes2, ok, stillOut] = repairEjection(P, routes, rem, lam);
                if ok && isempty(stillOut)
                    routes = routes2;
                    aux.eliminated = true;
                else
                    routes = snapshot;
                end
                aux.repaired = ok;
                aux.removed = numel(rem);
            end
        case 5
            q = randi([max(2, round(0.02 * P.n)), max(3, round(0.06 * P.n))]);
            [routes, rem] = destroyWorst(P, routes, q, lam);
            [routes, ok] = repairGreedy(P, routes, rem, lam, ctr);
            aux.repaired = ok;
        case 6
            % light random kick, then greedy repair (local refinement)
            q = randi([2, max(3, round(0.04 * P.n * sc))]);
            [routes, rem] = destroyRandom(P, routes, q);
            [routes, ok] = repairGreedy(P, routes, rem, lam, ctr);
            aux.repaired = ok;
        case 7
            q = randi([2, max(3, round(0.06 * P.n))]);
            [routes, rem] = destroyRandom(P, routes, q);
            [routes, ok] = repairRegret(P, routes, rem, lam, ctr, 2);
            aux.repaired = ok;
        case 8
            if isempty(ctx.elite)
                [routes, rem] = destroyRandom(P, routes, max(2, round(0.02 * P.n * sc)));
                [routes, ok] = repairGreedy(P, routes, rem, lam, ctr);
                aux.repaired = ok;
            else
                e = ctx.elite{randi(numel(ctx.elite))};
                [routes, aux] = pathRelink(P, routes, e, lam, ctr, sc);
            end
        case 9
            [routes, aux] = stringMoveMulti(P, routes, lam, sc);
        otherwise
            error('rlgbka_ops:id', 'unknown operator %d', id);
    end
end


% ================================================================ helpers

function o = setdef(o, f, v)
    if ~isfield(o, f), o.(f) = v; end
end

function allC = collectAll(routes)
    allC = zeros(0, 1);
    for r = 1:numel(routes)
        allC = [allC; routes{r}(:)]; %#ok<AGROW>
    end
    allC = allC(:)';
end

function routes = removeCustomers(P, routes, list)
    for i = 1:numel(list)
        c = list(i);
        for r = 1:numel(routes)
            pos = find(routes{r} == c, 1);
            if ~isempty(pos)
                routes{r}(pos) = [];
                break;
            end
        end
    end
end

% ------------------------------------------------------------- destroy 1
function [routes, rem] = destroyFar(P, routes, q)
    allC = collectAll(routes);
    q = min(q, numel(allC));
    d = P.S.D(P.depot, allC);
    p = d / sum(d);
    rem = randsample_w(allC, q, p);
    routes = removeCustomers(P, routes, rem);
end

% ------------------------------------------------------------- destroy 2
function [routes, rem] = destroyRelated(P, routes, q)
    allC = collectAll(routes);
    q = min(q, numel(allC));
    seed = allC(randi(numel(allC)));
    D = P.S.D;
    d = D(seed, allC) / max(1, max(D(:)));
    tw = abs(P.ready(allC) - P.ready(seed)) / max(1, max(P.due));
    rel = d + tw;
    [~, ord] = sort(rel, 'ascend');
    rem = allC(ord(1:q));
    routes = removeCustomers(P, routes, rem);
end

% ------------------------------------------------------------- destroy 3
function [routes, rem] = destroyRandom(P, routes, q)
    allC = collectAll(routes);
    q = min(q, numel(allC));
    rem = allC(randperm(numel(allC), q));
    routes = removeCustomers(P, routes, rem);
end

% ------------------------------------------------------------- destroy 4
function [routes, eliminated, rem] = destroyRoute(P, routes, lam)
%DESTROYROUTE  Target the route with the FEWEST customers for elimination.
%
%   Emptying the smallest route is the cheapest possible reduction of the
%   fleet, and choosing it (rather than a random route) makes the operator far
%   more likely to succeed when it is called.
    eliminated = false;
    rem = [];
    sizes = cellfun(@numel, routes);
    sizes(sizes == 0) = inf;
    [~, r] = min(sizes);
    if ~isfinite(sizes(r)) || numel(nonzeroCells(routes)) <= 1
        return;
    end
    rem = routes{r};
    routes(r) = [];          % drop the SLOT, so repair cannot refill it
end

function k = nonzeroCells(routes)
    k = find(~cellfun(@isempty, routes));
end

% ------------------------------------------------------------- destroy 5
function [routes, rem] = destroyWorst(P, routes, q, lam)
    rows = zeros(0, 2);
    dep = P.depot;
    for r = 1:numel(routes)
        rt = routes{r};
        L = numel(rt);
        for k = 1:L
            a = dep; if k > 1, a = rt(k-1); end
            b = dep; if k < L, b = rt(k+1); end
            c = rt(k);
            sav = P.S.D(a, c) + P.S.D(c, b) - P.S.D(a, b);
            rows(end+1, :) = [c, sav]; %#ok<AGROW>
        end
    end
    if isempty(rows), rem = []; return; end
    [~, ord] = sort(rows(:, 2), 'descend');
    ord = ord(1:min(q, numel(ord)));
    rem = rows(ord, 1)';
    routes = removeCustomers(P, routes, rem);
end

% ---------------------------------------------------------------- repair
function [routes, ok, stillOut] = repairPenalized(P, routes, rem, lam)
%REPAIRPENALIZED  Reinsert without requiring feasibility; minimise penalised cost.
%
%   Used by the route-elimination operator only.  Ordinary repair asks "where
%   can this customer legally go", and the answer is nowhere once the surviving
%   routes are full.  Here the question becomes "where does this customer hurt
%   least, in penalised terms", which always has an answer, so a route can
%   actually be emptied and the penalty can be repaired later by the search.
%
%   stillOut lists customers that could not be placed at all (fleet too small);
%   they are appended as their own route so none is ever silently dropped.
    ok = true;
    stillOut = [];
    pend = rem(:)';
    dep = P.depot;
    S = P.S;
    KEEP = 5;      % positions that receive an exact route evaluation

    while ~isempty(pend)
        % TWO-STAGE CANDIDATE FILTERING
        % The earlier version evaluated the full route at every position of every
        % route for every pending customer: 22 routes x ~10 positions x ~10
        % customers is 2,200 route evaluations per call, which is why route
        % elimination cost 47 ms while the string move cost 0.9 ms -- a 50x
        % spread that let the policy farm the cheap operator instead of choosing
        % on merit.  The distance change of an insertion is O(1) from the
        % distance matrix, so all positions are ranked on that and only the best
        % few are scored exactly.  Same scheme as vrp_insert_penalized, which had
        % simply never been applied here.
        bestC = 0; bestDelta = inf; bestR = 0; bestP = 0;

        for i = 1:numel(pend)
            j = pend(i);

            candR = zeros(0,1); candP = zeros(0,1); candD = zeros(0,1);
            for r = 1:numel(routes)
                rt = routes{r};
                for p = 0:numel(rt)
                    a = dep; if p > 0, a = rt(p); end
                    b = dep; if p < numel(rt), b = rt(p+1); end
                    d = S.D(a, j) + S.D(j, b) - S.D(a, b);

                    if numel(candD) < KEEP
                        candR(end+1,1) = r; candP(end+1,1) = p + 1; candD(end+1,1) = d; %#ok<AGROW>
                        [candD, o] = sort(candD); candR = candR(o); candP = candP(o);
                    elseif d < candD(end)
                        candD(end) = d; candR(end) = r; candP(end) = p + 1;
                        [candD, o] = sort(candD); candR = candR(o); candP = candP(o);
                    end
                end
            end

            for k = 1:numel(candR)
                r = candR(k); p = candP(k);
                rt = routes{r};
                cand = [rt(1:p-1), j, rt(p:end)];
                d = routePen(P, cand, lam) - routePen(P, rt, lam);
                if d < bestDelta
                    bestDelta = d; bestC = j; bestR = r; bestP = p;
                end
            end
        end
        if bestC == 0
            ok = false;
            stillOut = pend;
            break;
        end
        rt = routes{bestR};
        routes{bestR} = [rt(1:bestP-1), bestC, rt(bestP:end)];
        pend(pend == bestC) = [];
    end
end

function rp = routePen(P, rt, lam)
    if isempty(rt), rp = 0; return; end
    st = P.stats(rt);
    rp = st.dist + lam.cap * st.capExcess + lam.tw * st.twExcess;
end

function [routes, ok] = repairGreedy(P, routes, rem, lam, ctr) %#ok<INUSD>
%REPAIRGREEDY  Delegates to the validated repair in 09_solvers.
%
%   This file used to carry its own copy of the greedy repair.  Measured on
%   R1_2_1, RL-GBKA never improved the constructive solution in 1,679 iterations
%   across three separate runs, while ALNS -- which uses vrp_repair_greedy from
%   09_solvers on the identical starting solution -- reached 4936 from 6327.87.
%   Two implementations of the same operator had silently diverged, and the copy
%   here was the broken one.  There is now one implementation, in 09_solvers,
%   used by every solver in the project.
    [routes, ok] = vrp_repair_greedy(P, routes, rem, lam);
end

function [routes, ok] = repairRegret(P, routes, rem, lam, ctr, k) %#ok<INUSD>
%REPAIRREGRET  Delegates to the validated regret-k repair in 09_solvers.
    if nargin < 6 || isempty(k), k = 2; end
    [routes, ok] = vrp_repair_regret(P, routes, rem, lam, k);
end

function routes = doInsert(routes, r, p, c)
    if r > numel(routes)
        routes{end+1} = c;
    else
        rt = routes{r};
        routes{r} = [rt(1:p-1), c, rt(p:end)];
    end
end
function [routes, aux] = pathRelink(P, routes, elite, lam, ctr, sc)
%PATHRELINK  Discrete version of "move toward the leading solution".
%
%   GBKA pulls a candidate toward the alpha wolf by vector arithmetic, which has
%   no meaning on permutations.  The equivalent here is to pull the candidate
%   toward a stored elite solution one customer at a time: find customers whose
%   position differs most between the two, take them out, and reinsert them so
%   the route order moves closer to the elite's.
    aux = struct('repaired', true, 'eliminated', false, 'removed', 0);

    % customers whose successor differs between the two solutions
    curSucc = successorMap(routes);
    eliSucc = successorMap(elite);

    common = intersect(cell2mat(curSucc.keys), cell2mat(eliSucc.keys));
    diff = [];
    for i = 1:numel(common)
        c = common(i);
        if curSucc(c) ~= eliSucc(c)
            diff(end+1) = c; %#ok<AGROW>
        end
    end
    if isempty(diff), return; end

    q = min(numel(diff), max(2, round(0.10 * P.n * sc)));
    pick = diff(randperm(numel(diff), q));
    routes = removeCustomers(P, routes, pick);
    aux.removed = q;
    [routes, ok] = repairGreedy(P, routes, pick, lam, ctr);
    aux.repaired = ok;
end

function m = successorMap(routes)
    dep = 0;
    m = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for r = 1:numel(routes)
        rt = routes{r};
        for k = 1:numel(rt)
            if k < numel(rt)
                m(rt(k)) = rt(k+1);
            else
                m(rt(k)) = -r;   % end of route r: distinct per route
            end
        end
    end
    if isempty(m) %#ok<*NASGU>
        m = containers.Map('KeyType', 'double', 'ValueType', 'double');
    end
end

function s = randsample_w(pop, k, w)
%RANDSAMPLE_W  Draw k DISTINCT members, probability proportional to w.
%
%   Without replacement: a destroy operator that removes the same customer twice
%   leaves the second removal a no-op, so the effective removal size silently
%   shrinks and the operator stops doing what its name says.
    pop = pop(:)';
    w = w(:)' / sum(w);
    k = min(k, numel(pop));
    s = zeros(1, k);
    for i = 1:k
        c = cumsum(w);
        idx = find(rand <= c, 1, 'first');
        if isempty(idx), idx = numel(pop); end
        s(i) = pop(idx);
        pop(idx) = [];
        w(idx) = [];
        if isempty(w), break; end
        w = w / sum(w);
    end
end

% ================================================================ operator 9

function [routes, aux] = stringMove(P, routes, lam, sc)
%STRINGMOVE  Relocate a contiguous block of customers as one unit.
%
%   WHY THIS OPERATOR EXISTS
%   On R1_2_1 the time-window width has median 10 while travel times between
%   customers are of the order of tens.  Removing a SINGLE customer and
%   reinserting it anywhere else shifts its service start by more than the
%   window allows, so destroy-and-reinsert is almost a no-op there: 7,859
%   iterations produced 7 improvements, and the search never left the
%   constructive solution.
%
%   Moving a BLOCK behaves differently.  The relative timing inside the block is
%   preserved; only the block's start time shifts.  A block that was feasible in
%   one place therefore remains internally feasible in another, and only the
%   block's own windows need to be re-checked against the new start.  This is
%   the mechanism behind string-based neighbourhoods (SISR, Christiaens &
%   Vanden Berghe 2020), which were designed for exactly this regime.
%
%   WHY IT IS CHEAP
%   The scoring of every insertion point only needs the change in distance,
%   which is O(1) from the distance matrix.  Only the best few positions are
%   then evaluated exactly, the same two-stage trick used by
%   vrp_insert_penalized.  A full scan therefore costs a few milliseconds
%   instead of a few hundred.
%
%   Unlike the destroy-repair operators this one does not hand the customers to
%   a repair heuristic -- the block goes back in as a unit, which is the whole
%   point.

    aux = struct('repaired', false, 'eliminated', false, 'removed', 0);

    dep = P.depot;
    S   = P.S;

    sizes = cellfun(@numel, routes);
    src = find(sizes >= 2);
    if isempty(src), return; end

    r1  = src(randi(numel(src)));
    L1  = sizes(r1);
    len = min(L1, randi([2, max(2, round(min(6, L1) * sc))]));
    p1  = randi(L1 - len + 1);
    seg = routes{r1}(p1:p1+len-1);
    rest = routes{r1}([1:p1-1, p1+len:end]);

    KEEP = 5;
    candR = zeros(0, 1); candP = zeros(0, 1); candD = zeros(0, 1);

    for r = 1:numel(routes)
        if r == r1
            base = rest;
        else
            base = routes{r};
        end
        for pp = 0:numel(base)
            a = dep; if pp > 0, a = base(pp); end
            b = dep; if pp < numel(base), b = base(pp+1); end
            d = S.D(a, seg(1)) + S.D(seg(end), b) - S.D(a, b);

            if numel(candD) < KEEP
                candR(end+1,1) = r; candP(end+1,1) = pp + 1; candD(end+1,1) = d; %#ok<AGROW>
                [candD, o] = sort(candD); candR = candR(o); candP = candP(o);
            elseif d < candD(end)
                candD(end) = d; candR(end) = r; candP(end) = pp + 1;
                [candD, o] = sort(candD); candR = candR(o); candP = candP(o);
            end
        end
    end

    bestCost = inf; bestR = 0; bestBlock = [];
    for i = 1:numel(candR)
        r = candR(i); pp = candP(i);
        if r == r1
            base = rest;
        else
            base = routes{r};
        end
        block = [base(1:pp-1), seg, base(pp:end)];

        % Inserting the block back where it came from reconstructs the original
        % route: a guaranteed no-op that consumes a decision.  Skipping it is
        % what makes this a move operator rather than an occasional no-op.
        if r == r1 && isequal(block, routes{r1})
            continue;
        end

        c = routePenOf(P, block, lam);
        if c < bestCost
            bestCost = c; bestR = r; bestBlock = block;
        end
    end

    if bestR == 0, return; end

    % The move is applied unconditionally -- including an in-route reordering
    % that makes the route slightly worse.  Letting the simulated-annealing step
    % in the main loop decide acceptance is what keeps the search able to move
    % sideways; gating on improvement here made the operator dead most of the
    % time, which is exactly how it behaved on the first attempt.
    routes{r1} = rest;
    routes{bestR} = bestBlock;
    aux.removed = len;
end

function rp = routePenOf(P, rt, lam)
    if isempty(rt), rp = 0; return; end
    st = P.stats(rt);
    rp = st.dist + lam.cap * st.capExcess + lam.tw * st.twExcess;
end

function [routes, aux] = stringMoveMulti(P, routes, lam, sc)
%STRINGMOVEMULTI  Several block moves per call, to match the other operators' cost.
%
%   A single block move costs about 0.9 ms, twenty to fifty times less than route
%   elimination or elite relinking.  Under a time budget that is a structural
%   advantage: the policy can pick the cheap move far more often and collect more
%   reward events for the same CPU, which is exactly the collapse observed at
%   99.97% of decisions.  Cost parity is therefore a precondition for the policy
%   choosing on merit rather than on price.
%
%   Rather than pad the operator with artificial work it performs a short greedy
%   descent: up to NREP block moves, each kept only if the penalised cost
%   improves.  That makes it a stronger operator, not merely a slower one, and
%   brings its cost into line with the other three.
    NREP = 12;

    aux = struct('repaired', false, 'eliminated', false, 'removed', 0);

    cur = routes;
    bestCost = routesPen(P, cur, lam);

    for k = 1:NREP
        [cand, a] = stringMove(P, cur, lam, sc);
        if a.removed == 0, break; end
        aux.removed = aux.removed + a.removed;
        c = routesPen(P, cand, lam);
        if c < bestCost - 1e-9
            cur = cand;
            bestCost = c;
        elseif k >= 4
            break;
        end
    end

    routes = cur;
end

function c = routesPen(P, routes, lam)
%ROUTESPEN  Total penalised cost of a whole solution.
%
%   stringMoveMulti compares whole solutions, so it needs the sum over routes
%   rather than the cost of one route.  Passing the cell array to the per-route
%   helper raised "cannot use a cell as an index" the first time it ran.
    c = 0;
    for r = 1:numel(routes)
        if isempty(routes{r}), continue; end
        c = c + routePenOf(P, routes{r}, lam);
    end
end

function [routes, ok, stillOut] = repairEjection(P, routes, rem, lam)
%REPAIREJECTION  Reinsert by ejecting, never by violating.
%
%   WHY THIS REPLACES PENALISED REINSERTION
%   Route elimination used to reinsert by minimising penalised cost, which by
%   construction produces a solution that VIOLATES a capacity or a time window and
%   relies on the search later repairing it.  That was compatible with the old
%   acceptance rule, which accepted infeasible candidates.  Once the acceptance
%   rule was corrected to reject every infeasible candidate -- the single change
%   that took C1_2_1 from 21 vehicles to 20 -- route elimination could no longer
%   contribute anything at all: measured at 1,718 calls and zero improvements on
%   R1_2_1.
%
%   An ejection chain keeps the move feasible throughout.  If a removed customer
%   fits nowhere, a customer is ejected from a route to make room, and the ejected
%   customer is then placed in turn.  The route that was emptied therefore stays
%   empty, which is the only way this operator can reduce the fleet under a
%   feasibility-preserving acceptance rule.
%
%   Depth is bounded by the ejection budget so a single call cannot cascade
%   through the whole solution; when the budget runs out the operator gives up and
%   returns the original routes, so it can never leave a customer unserved.

    ok = true;
    stillOut = [];
    dep = P.depot;

    pend = rem(:)';
    BUDGET = min(2, numel(pend));   % at most two ejections per call, to keep the cost bounded
    used = 0;

    while ~isempty(pend)
        c = pend(1);
        placed = false;

        % ---- direct feasible insertion first
        [routes, p] = insertBestFeasible(P, routes, c);
        if p > 0
            pend(1) = [];
            placed = true;
        end

        % ---- otherwise eject
        if ~placed && used < BUDGET
            bestR = 0; bestPos = 0; bestEject = 0; bestCost = inf;
            for r = 1:numel(routes)
                rt = routes{r};
                for k = 1:numel(rt)
                    e = rt(k);
                    shorter = rt([1:k-1, k+1:end]);
                    trial = routes; trial{r} = shorter;
                    [trial, pos] = insertBestFeasible(P, trial, c);
                    if pos == 0, continue; end
                    st = P.stats(trial{r});
                    if st.capExcess > 0 || st.twExcess > 0, continue; end
                    cost = st.dist;
                    if cost < bestCost
                        bestCost = cost; bestR = r; bestEject = e; bestPos = pos;
                    end
                end
            end

            if bestR > 0
                rt = routes{bestR};
                k = find(rt == bestEject, 1);
                routes{bestR} = rt([1:k-1, k+1:end]);
                [routes, pos] = insertBestFeasible(P, routes, c);
                if pos > 0
                    pend(1) = [];
                    pend(end+1) = bestEject; %#ok<AGROW>
                    used = used + 1;
                    placed = true;
                end
            end
        end

        if ~placed
            % no feasible home even with ejections: give up, leave solution intact
            ok = false;
            stillOut = pend;
            return;
        end
    end
end

function [routes, pos] = insertBestFeasible(P, routes, c)
%INSERTBESTFEASIBLE  Best feasible position for c, or pos = 0 if none.
%
%   Two-stage filtering again.  Evaluating every position of every route exactly
%   made the ejection chain cost 1,047 ms per call -- a hundred times the target --
%   because a single ejection candidate does one full insertion scan and the
%   operator tries hundreds of candidates.  Ranking positions on the O(1) distance
%   change and scoring only the best few brings a scan down to a handful of route
%   evaluations.
    pos = 0;
    KEEP = 3;
    dep = P.depot;
    S = P.S;

    candR = zeros(0,1); candP = zeros(0,1); candD = zeros(0,1);
    for r = 1:numel(routes)
        rt = routes{r};
        for p = 1:numel(rt)+1
            a = dep; if p > 1, a = rt(p-1); end
            b = dep; if p <= numel(rt), b = rt(p); end
            d = S.D(a, c) + S.D(c, b) - S.D(a, b);
            if numel(candD) < KEEP
                candR(end+1,1) = r; candP(end+1,1) = p; candD(end+1,1) = d; %#ok<AGROW>
                [candD, o] = sort(candD); candR = candR(o); candP = candP(o);
            elseif d < candD(end)
                candD(end) = d; candR(end) = r; candP(end) = p;
                [candD, o] = sort(candD); candR = candR(o); candP = candP(o);
            end
        end
    end

    bestCost = inf; bestR = 0; bestPos = 0;
    for k = 1:numel(candR)
        r = candR(k); p = candP(k);
        rt = routes{r};
        cand = [rt(1:p-1), c, rt(p:end)];
        st = P.stats(cand);
        if st.capExcess > 0 || st.twExcess > 0, continue; end
        d = st.dist - P.stats(rt).dist;
        if d < bestCost
            bestCost = d; bestR = r; bestPos = p;
        end
    end

    if bestR > 0
        rt = routes{bestR};
        routes{bestR} = [rt(1:bestPos-1), c, rt(bestPos:end)];
        pos = bestPos;
    end
end
