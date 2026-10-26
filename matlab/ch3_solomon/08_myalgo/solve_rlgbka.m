function [best, out] = solve_rlgbka(P, opts)
%SOLVE_RLGBKA  GBKA's strategy layer driven by a reinforcement-learned scheduler.
%
%   [best, out] = solve_rlgbka(P, opts)
%
%   P      problem adapter (problem_static for the benchmarks; a time-dependent
%          adapter with the same handles for the road-network case)
%   opts   .budget .seed .policy .decideEvery .eliteSize .vehWeight
%          .lamCap .lamTw .record
%
%   out    .dist .nveh .feasible .ffe .iter .curve .opUse .opSucc
%          .traj (only when opts.record is true)
%
% WHAT IS KEPT FROM GBKA, AND WHAT IS NOT
%   Kept:      multi-operator portfolio, adaptive scheduling, elite archive,
%              stagnation handling.
%   Replaced:  the continuous arithmetic (grey-wolf averaging, golden sine,
%              opposition) which is undefined or NP-hard on permutations.
%              The scheduling rule that GBKA hand-tuned is now a learned policy.
%
% THE SCHEDULING LOOP
%   Every `decideEvery` iterations the policy observes a 24-dimensional summary
%   of the search state and picks one of eight operators.  The operator is
%   applied, the result is accepted by a simulated-annealing test, and the
%   per-operator success counts are updated.  Those counts are themselves part
%   of the state, so the policy sees how each choice has recently paid off.
%
% FLEET SIZE
%   The number of vehicles is part of the objective (weight `vehWeight`) rather
%   than fixed, because operator 4 exists specifically to eliminate routes.
%   This is the structural difference from the four baselines, which cannot
%   change their fleet size at all once it is fixed.

    if nargin < 2, opts = struct(); end
    opts = setdef(opts, 'budget',      30000);
    opts = setdef(opts, 'seed',            1);
    opts = setdef(opts, 'policy',         []);
    opts = setdef(opts, 'decideEvery',    20);
    opts = setdef(opts, 'eliteSize',       8);
    opts = setdef(opts, 'vehWeight',    1000);
    opts = setdef(opts, 'lamCap',         50);
    opts = setdef(opts, 'lamTw',           5);
    opts = setdef(opts, 'record',      false);
    opts = setdef(opts, 'verbose',     false);
    opts = setdef(opts, 'opSet',       1:8);

    rng(opts.seed);

    % The policy's action space is indexed over the ALLOWED operators only; the
    % index is mapped to an operator id here.  That mapping is what makes a
    % leave-one-out ablation a one-line change rather than a rewrite.
    opSet = opts.opSet(:)';
    nAct = numel(opSet);

    pol = opts.policy;
    if isempty(pol)
        pol = rlgbka_policy_init(struct('seed', opts.seed, 'A', nAct));
    end
    if size(pol.W3, 2) ~= nAct
        error('solve_rlgbka:actionSpace', ...
              'policy has %d actions but opSet has %d', size(pol.W3, 2), nAct);
    end

    ctr = ffe_budget(opts.budget);
    lam = struct('cap', opts.lamCap, 'tw', opts.lamTw);
    vehW = opts.vehWeight;

    % ------------------------------------------------------------- start
    x = P.construct();
    [fx, Rx] = objective(P, x, lam, vehW);
    ctr.hit();
    startDist = Rx.dist;

    elite = {x};
    eliteKey = [Rx.nveh, Rx.dist];

    best = {};
    bestKey = [inf, inf];              % lexicographic (vehicles, distance)
    if Rx.feasible
        best = x; bestKey = [Rx.nveh, Rx.dist];
    end

    opUse = zeros(1, 8);
    opSucc = zeros(1, 8);
    recentUse = zeros(1, 8);
    recentSucc = zeros(1, 8);

    % SA temperature: accept a 2% worse objective with probability 0.5 at the start
    T0 = 0.02 * max(abs(fx), 1) / log(2);
    T = T0;
    cool = 0.9995;

    stagnation = 0;
    window = 200;

    trS = zeros(0, 24);
    trA = zeros(0, 1);
    trR = zeros(0, 1);
    rAccum = 0;
    pendingDecision = false;
    scaleR = max(startDist, 1);

    curve = zeros(1, 0);
    chk = max(1, floor(opts.budget / 40));
    nextChk = chk;

    a = 1;
    actIter = 0;
    it = 0;

    while ~ctr.exhausted()
        it = it + 1;

        % ------------------------------------------------- policy decision
        if mod(it - 1, opts.decideEvery) == 0
            % close the reward window of the previous decision
            if pendingDecision
                trR(end+1, 1) = rAccum; %#ok<AGROW>
            end
            rAccum = 0;
            pendingDecision = true;

            fstate = makeState(fx, bestKey(2), startDist, stagnation, window, ...
                               Rx, P, elite, eliteKey, ...
                               recentSucc, recentUse, ctr);
            if opts.record
                [a, ~, ~] = rlgbka_policy(pol, fstate, 'sample');
                trS(end+1, :) = fstate; %#ok<AGROW>
                trA(end+1, 1)  = a;     %#ok<AGROW>
            else
                a = rlgbka_policy(pol, fstate, 'sample');
            end
            actIter = it;
        end

        % ----------------------------------------------------- apply
        opId = opSet(a);
        ctx = struct('lam', lam, 'ctr', ctr, 'elite', {elite}, 'vehWeight', vehW);
        [cand, aux] = rlgbka_ops(opId, P, x, ctx);
        [fc, Rc] = objective(P, cand, lam, vehW);
        ctr.hit();

        opUse(a) = opUse(a) + 1;
        recentUse(a) = recentUse(a) + 1;

        % --------------------------------------------------- acceptance
        improved = fc < fx - 1e-9;
        if improved
            opSucc(a) = opSucc(a) + 1;
            recentSucc(a) = recentSucc(a) + 1;
        end

        accept = improved || rand < exp(-(fc - fx) / max(T, 1e-9));
        if accept
            % reward = improvement in the solver's own objective, normalised.
            % Using the penalised objective (which contains W * nveh) is what
            % makes route elimination immediately rewarding: it looks bad on
            % distance and violation but still lowers f substantially, so the
            % policy receives credit for it without having to wait for the
            % repair that follows.
            rAccum = rAccum + (fx - fc) / scaleR;
            x = cand; fx = fc; Rx = Rc;
        end

        % ------------------------------------------------- best + elite
        if Rc.feasible
            key = [Rc.nveh, Rc.dist];
            if isBetter(key, bestKey)
                best = cand; bestKey = key;
                stagnation = 0;
            else
                stagnation = stagnation + 1;
            end
            [elite, eliteKey] = pushElite(elite, eliteKey, cand, key, opts.eliteSize);
        else
            stagnation = stagnation + 1;
        end

        % ---------------------------------------------------- lambda
        if Rx.capExcess > 0 || Rx.twExcess > 0
            lam.cap = min(lam.cap * 1.01, 1e5);
            lam.tw  = min(lam.tw  * 1.01, 1e5);
        else
            lam.cap = max(lam.cap * 0.99, 1);
            lam.tw  = max(lam.tw  * 0.99, 0.5);
        end

        T = T * cool;

        % -------------------------------------------------- recent stats decay
        if mod(it, 50) == 0
            recentUse  = recentUse  * 0.5;
            recentSucc = recentSucc * 0.5;
        end

        if ctr.used() >= nextChk
            curve(end+1) = bestKey(2); %#ok<AGROW>
            nextChk = nextChk + chk;
            if opts.verbose
                fprintf('  it %6d ffe %7d best %d/%8.2f  cur %d/%8.2f  a=%d  lam %.0f/%.1f\n', ...
                        it, ctr.used(), bestKey(1), bestKey(2), Rx.nveh, Rx.dist, a, ...
                        lam.cap, lam.tw);
            end
        end
    end

    % ------------------------------------------------------------- output
    if isempty(best)
        warning('solve_rlgbka:nofeasible', ...
                'no feasible solution found; returning the least violating one');
        best = x;
    end
    R = P.evalReport(best);

    out = struct('dist', R.cost, 'nveh', R.nveh, 'feasible', R.feasible, ...
                 'ffe', ctr.used(), 'iter', it, 'curve', curve, ...
                 'opUse', opUse, 'opSucc', opSucc, ...
                 'startDist', startDist, ...
                 'improve', 100 * (startDist - R.cost) / max(startDist, 1e-9));

    if opts.record
        if pendingDecision
            trR(end+1, 1) = rAccum; %#ok<AGROW>
        end
        % terminal reward: feasibility and final quality, so the policy is told
        % that an infeasible trajectory is worth nothing however good it looked
        if ~isempty(best)
            terminal = (startDist - R.cost) / scaleR;
        else
            terminal = -1;
        end
        n = min([numel(trA), numel(trR), size(trS, 1)]);
        trS = trS(1:n, :); trA = trA(1:n); trR = trR(1:n);
        if n > 0
            trR(n) = trR(n) + terminal;
        end
        out.traj = struct('S', trS, 'A', trA, 'r', trR, ...
                          'return', sum(trR), 'dist', R.cost, ...
                          'nveh', R.nveh, 'feasible', R.feasible);
    end
end


% ================================================================ helpers

function o = setdef(o, f, v)
    if ~isfield(o, f), o.(f) = v; end
end

function [f, R] = objective(P, routes, lam, vehW)
    [fp, ~, R] = P.eval(routes, lam);
    f = fp + vehW * R.nveh;
end

function tf = isBetter(a, b)
    if a(1) < b(1), tf = true; return; end
    tf = (a(1) == b(1)) && (a(2) < b(2) - 1e-9);
end

function [elite, key] = pushElite(elite, key, cand, newKey, maxSize)
    for i = 1:size(key, 1)
        if isBetter(newKey, key(i, :))
            elite = [{cand}, elite];
            key = [newKey; key];
            break;
        end
    end
    if numel(elite) > maxSize
        elite = elite(1:maxSize);
        key = key(1:maxSize, :);
    end
end

function s = makeState(fx, bestDist, scale, stagnation, window, Rx, P, ...
                      elite, eliteKey, recentSucc, recentUse, ctr)
    f = struct();
    f.f          = fx;
    f.fBest      = bestDist;
    f.scale      = scale;
    f.stagnation = stagnation;
    f.window     = window;
    f.nveh       = Rx.nveh;
    f.m          = max(P.m, 1);
    f.capExcess  = Rx.capExcess;
    f.twExcess   = Rx.twExcess;
    f.nDemand    = sum(P.demand);
    f.horizon    = max(P.due);
    f.eliteBest  = min(eliteKey(:, 2));
    if numel(elite) > 1
        ds = zeros(0, 1);
        for i = 1:numel(elite)-1
            ds(end+1, 1) = routeDiff(elite{i}, elite{i+1}); %#ok<AGROW>
        end
        f.eliteDiv = mean(ds);
    else
        f.eliteDiv = 0;
    end
    f.opSucc = recentSucc;
    f.opUse  = recentUse;
    f.progress = min(1, ctr.used() / max(ctr.budget, 1));
    s = rlgbka_features(f);
end

function d = routeDiff(a, b)
%ROUTEDIFF  Crude dissimilarity: 1 minus the Jaccard overlap of successor pairs.
    sa = successorPairs(a);
    sb = successorPairs(b);
    if isempty(sa) || isempty(sb), d = 1; return; end
    inter = numel(intersect(sa, sb));
    d = 1 - inter / numel(union(sa, sb));
end

function p = successorPairs(routes)
    p = zeros(0, 1);
    for r = 1:numel(routes)
        rt = routes{r};
        for k = 1:numel(rt)-1
            p(end+1, 1) = rt(k) * 100000 + rt(k+1); %#ok<AGROW>
        end
    end
end
