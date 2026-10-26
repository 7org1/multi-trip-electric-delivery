function [best, out] = solve_alns(S, opts)
%SOLVE_ALNS  Adaptive large neighbourhood search for the VRPTW.
%
%   [best, out] = solve_alns(S, opts)
%
%   S      model struct from vrptw_model
%   opts   (all optional)
%          .maxIter    iterations, default 25000
%          .segLen     iterations per weight update, default 100
%          .seed       RNG seed, default 1
%          .vehWeight  penalty per vehicle in the scalarised objective,
%                      default 1000
%          .timeLimit  seconds, default inf
%          .verbose    default false
%
%   best   best feasible solution found (cell array of routes)
%   out    .cost .nveh .iter .curve (best scalarised cost every segLen
%          iterations) .gapToBKS (filled in by the caller)
%
% OBJECTIVE
%   Benchmarks rank solutions by (vehicles, distance).  The search uses the
%   scalarisation  f = distance + vehWeight * nveh  which is exact whenever
%   vehWeight exceeds the largest distance that removing a vehicle could save.
%
% OPERATORS
%   destroy : random, worst, related (Shaw), whole-route
%   repair  : greedy, regret-2
%   Weights adapt by Ropke-Pisinger scoring: a new global best scores 33, an
%   accepted improvement 9, an accepted worsening 13.

    if nargin < 2, opts = struct(); end
    opts = setdef(opts, 'maxIter',   25000);
    opts = setdef(opts, 'segLen',      100);
    opts = setdef(opts, 'seed',          1);
    opts = setdef(opts, 'vehWeight',  1000);
    opts = setdef(opts, 'timeLimit',   inf);
    opts = setdef(opts, 'verbose',   false);

    rng(opts.seed);

    dNames = {'random','worst','related','route'};
    rNames = {'greedy','regret2'};
    nD = numel(dNames); nR = numel(rNames);
    wD = ones(1, nD);  wR = ones(1, nR);
    sD = zeros(1, nD); sR = zeros(1, nR);
    aD = zeros(1, nD); aR = zeros(1, nR);

    cur = vrptw_construct(S);
    curCost = scalar(S, cur, opts.vehWeight);
    best = cur;
    bestCost = curCost;

    T0 = 0.05 * abs(curCost) / log(2);     % 5% worse accepted with prob 0.5
    T  = T0;
    cool = 0.99975;

    curve = zeros(floor(opts.maxIter / opts.segLen) + 1, 1);
    ci = 1;
    curve(ci) = bestCost;
    tStart = tic;

    for it = 1:opts.maxIter
        % ------------------------------------------------ roulette selection
        di = roulette(wD); ri = roulette(wR);

        % ------------------------------------------------ destroy
        q = randi([1, max(2, min(30, ceil(0.25 * S.n)))]);
        [partial, removed] = applyDestroy(S, cur, q, dNames{di});
        if isempty(removed)
            continue;
        end

        % ------------------------------------------------ repair
        cand = applyRepair(S, partial, removed, rNames{ri});
        candCost = scalar(S, cand, opts.vehWeight);

        % ------------------------------------------------ score + accept
        aD(di) = aD(di) + 1; aR(ri) = aR(ri) + 1;
        score = 0;
        if candCost < bestCost - 1e-9
            best = cand; bestCost = candCost;
            cur  = cand; curCost  = candCost;
            score = 33;
        elseif candCost < curCost - 1e-9
            cur = cand; curCost = candCost;
            score = 9;
        elseif rand < exp(-(candCost - curCost) / max(T, 1e-9))
            cur = cand; curCost = candCost;
            score = 13;
        end
        sD(di) = sD(di) + score;
        sR(ri) = sR(ri) + score;

        T = T * cool;

        % ------------------------------------------------ weight update
        if mod(it, opts.segLen) == 0
            wD = updateW(wD, sD, aD); wR = updateW(wR, sR, aR);
            sD(:) = 0; sR(:) = 0; aD(:) = 0; aR(:) = 0;
            ci = ci + 1;
            if ci <= numel(curve), curve(ci) = bestCost; end
            if opts.verbose
                fprintf('  iter %6d  best %.2f  cur %.2f  T %.3f\n', ...
                        it, bestCost, curCost, T);
            end
        end

        if toc(tStart) > opts.timeLimit, break; end
    end

    curve = curve(1:min(ci, numel(curve)));

    % final robustness: if the best is somehow infeasible, re-construct
    R = vrptw_eval(S, best);
    if ~R.feasible
        warning('solve_alns:infeasible', ...
                'best solution infeasible; falling back to construction');
        best = vrptw_construct(S);
        R = vrptw_eval(S, best);
    end

    out = struct('cost', R.cost, 'nveh', R.nveh, 'iter', it, ...
                 'curve', curve, 'feasible', R.feasible);
end


% ================================================================ helpers

function o = setdef(o, f, v)
    if ~isfield(o, f), o.(f) = v; end
end

function c = scalar(S, routes, vehW)
    R = vrptw_eval(S, routes);
    c = R.cost + vehW * R.nveh;
    if ~R.feasible, c = c + 1e9; end
end

function i = roulette(w)
    w = max(w, 1e-6);
    cs = cumsum(w);
    i = find(rand * cs(end) <= cs, 1, 'first');
    if isempty(i), i = numel(w); end
end

function w = updateW(w, s, a)
    % Ropke-Pisinger: exponential smoothing, only for operators that were used
    rho = 0.1;
    used = a > 0;
    if any(used)
        w(used) = (1 - rho) * w(used) + rho * (s(used) ./ a(used));
    end
    w = max(w, 0.05);
end

function [routes, removed] = applyDestroy(S, routes, q, name)
    routes = routes(:)';

    allC = zeros(0, 1);
    for r = 1:numel(routes)
        allC = [allC; routes{r}(:)]; %#ok<AGROW>
    end
    allC = allC(:)';
    if isempty(allC)
        removed = []; return;
    end
    q = min(q, numel(allC));

    switch name
        case 'random'
            removed = allC(randperm(numel(allC), q));
        case 'worst'
            removed = worstIDs(S, routes, q);
        case 'related'
            seed = allC(randi(numel(allC)));
            removed = relatedIDs(S, allC, seed, q);
        case 'route'
            nonEmpty = find(~cellfun(@isempty, routes));
            r = nonEmpty(randi(numel(nonEmpty)));
            removed = routes{r};
        otherwise
            removed = allC(randperm(numel(allC), q));
    end

    for i = 1:numel(removed)
        c = removed(i);
        for r = 1:numel(routes)
            rt = routes{r};
            if isempty(rt), continue; end
            pos = find(rt == c, 1);
            if ~isempty(pos)
                routes{r} = rt([1:pos-1, pos+1:end]);
                break;
            end
        end
    end
end

function sav = removalSaving(S, routes)
%REMOVALSAVING  (customer, saving) for every customer currently routed.
    dep = S.depot;
    rows = [];
    for r = 1:numel(routes)
        rt = routes{r};
        L = numel(rt);
        for k = 1:L
            a = dep; if k > 1, a = rt(k-1); end
            b = dep; if k < L, b = rt(k+1); end
            c = rt(k);
            sav = S.D(a, c) + S.D(c, b) - S.D(a, b);
            rows(end+1, :) = [c, sav]; %#ok<AGROW>
        end
    end
    sav = rows;
end

function ids = worstIDs(S, routes, q)
    sav = removalSaving(S, routes);
    [~, ord] = sort(sav(:, 2), 'descend');
    ord = ord(1:min(q, numel(ord)));
    ids = sav(ord, 1)';
end

function ids = relatedIDs(S, allC, seedC, q)
    % relatedness: small distance and similar time window
    d = S.D(seedC, allC) / max(1, max(S.D(:)));
    tw = abs(S.ready(allC) - S.ready(seedC)) / max(1, max(S.due));
    rel = d + tw;
    [~, ord] = sort(rel, 'ascend');
    ids = allC(ord(1:min(q, numel(ord))));
end

function routes = applyRepair(S, routes, removed, name)
    switch name
        case 'greedy'
            routes = repairGreedy(S, routes, removed);
        case 'regret2'
            routes = repairRegret(S, routes, removed, 2);
        otherwise
            routes = repairGreedy(S, routes, removed);
    end
end

function routes = repairGreedy(S, routes, removed)
%REPAIRGREEDY  Insert customers one at a time, cheapest first.
%
% New routes are OPENED ONLY WHEN NOTHING FITS.  Allowing a new route on every
% candidate makes a fresh depot round trip look cheap, the repair keeps
% recreating routes that the destroy operator just removed, and the vehicle
% count never falls.  With m generous (50 slots for ~20 routes), that single
% detail decides whether ALNS can reach the best-known vehicle count at all.
    pend = removed(:)';
    while ~isempty(pend)
        bestC = 0; bestD = inf; bestR = 0; bestP = 0;
        for i = 1:numel(pend)
            j = pend(i);
            [r, p, d, found] = vrptw_insert_best(S, routes, j, false);
            if found && d < bestD
                bestD = d; bestC = j; bestR = r; bestP = p;
            end
        end
        if bestC == 0
            j = pend(1);
            [bestR, bestP, ~, found] = vrptw_insert_best(S, routes, j, true);
            bestC = j;
            if ~found
                bestR = numel(routes) + 1; bestP = 1;
            end
        end
        routes = doInsert(routes, bestR, bestP, bestC);
        pend(pend == bestC) = [];
    end
end

function routes = repairRegret(S, routes, removed, k)
%REPAIRREGRET  Regret-k insertion; see REPAIRGREEDY for the new-route policy.
    pend = removed(:)';
    while ~isempty(pend)
        bestC = 0; bestReg = -inf; bestR = 0; bestP = 0;
        for i = 1:numel(pend)
            j = pend(i);
            [r, p, d, found, per] = vrptw_insert_best(S, routes, j, false);
            if ~found, continue; end
            ds = per(:, 1);
            ds = sort(ds(~isnan(ds)));
            if isempty(ds), continue; end
            if numel(ds) >= k
                reg = sum(ds(2:k)) - ds(1) * (k - 1);
            elseif numel(ds) == 1
                reg = 0;         % only one option left: low priority
            else
                reg = ds(1);
            end
            reg = reg - 1e-6 * d;   % tie-break on absolute cost
            if reg > bestReg
                bestReg = reg; bestC = j; bestR = r; bestP = p;
            end
        end
        if bestC == 0
            j = pend(1);
            [bestR, bestP, ~, found] = vrptw_insert_best(S, routes, j, true);
            bestC = j;
            if ~found
                bestR = numel(routes) + 1; bestP = 1;
            end
        end
        routes = doInsert(routes, bestR, bestP, bestC);
        pend(pend == bestC) = [];
    end
end

function routes = doInsert(routes, r, p, c)
    if r > numel(routes)
        routes{end+1} = c;
    else
        rt = routes{r};
        routes{r} = [rt(1:p-1), c, rt(p:end)];
    end
end
