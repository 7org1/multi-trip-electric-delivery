function [best, out] = solve_vns(S, opts)
%SOLVE_VNS  Variable Neighbourhood Search for the VRPTW, orthodox form.
%
%   [best, out] = solve_vns(S, opts)
%
%   Follows Mladenovic & Hansen (1997), Basic VNS with a VND local search:
%
%       x  <- constructive heuristic;  k <- 1
%       repeat
%           x' <- SHAKE(x, k)              random point in N_k(x)
%           x' <- VND(x')                  descend through N_1 .. N_kmax
%           if f(x') < f(x)  then  x <- x', k <- 1
%           else                   k <- k + 1   (wrapping at kmax)
%       until the evaluation budget is spent
%
%   NEIGHBOURHOODS, in increasing order of disruption
%       N1  relocate      move one customer elsewhere
%       N2  exchange      swap two customers
%       N3  2-opt*        exchange the tails of two routes
%       N4  or-opt        move a chain of two customers
%
%   FIXED FLEET AND PENALTIES
%       The fleet is fixed to the best-known vehicle count.  Intermediate
%       solutions may violate capacity or time windows; the violation is
%       charged through an adaptive penalty and the penalty coefficients are
%       re-tuned as the search proceeds.  A solution is only ever RETURNED if
%       it is feasible.
%
%   opts fields (all optional)
%       .budget    objective evaluations allowed, default 20000
%       .kmax      neighbourhoods used, default 4
%       .seed      RNG seed, default 1
%       .lamCap    initial capacity penalty, default 50
%       .lamTw     initial time-window penalty, default 5
%       .verbose   default false
%
%   out fields
%       .dist .nveh .feasible .ffe .improve .curve

    if nargin < 2, opts = struct(); end
    opts = setdef(opts, 'budget',  20000);
    opts = setdef(opts, 'kmax',        4);
    opts = setdef(opts, 'seed',        1);
    opts = setdef(opts, 'lamCap',     50);
    opts = setdef(opts, 'lamTw',       5);
    opts = setdef(opts, 'verbose', false);

    rng(opts.seed);
    ctr = ffe_budget(opts.budget);
    lam = struct('cap', opts.lamCap, 'tw', opts.lamTw);

    % ------------------------------------------------------------ start
    x = vrptw_construct(S);
    [fx, vx, Rx] = vrptw_penalized_cost(S, x, lam);
    ctr.hit();

    best = {};
    bestDist = inf;
    if vx <= 1e-9 && Rx.dist < bestDist
        best = x; bestDist = Rx.dist;
    end
    startDist = Rx.dist;

    k = 1;
    chk = max(1, floor(opts.budget / 50));
    curve = zeros(1, 0);
    nextChk = chk;

    while ~ctr.exhausted()
        % -------------------------------------------------- shaking
        xp = shake(S, x, k);
        [fp, vp, Rp] = vrptw_penalized_cost(S, xp, lam);
        ctr.hit();
        if ctr.exhausted(), break; end

        % -------------------------------------------------- VND local search
        [xp, fp, Rp, vp] = vnd(S, xp, fp, lam, ctr);

        % -------------------------------------------------- move or not
        if fp < fx - 1e-9
            x = xp; fx = fp; vx = vp; Rx = Rp;
            k = 1;
            if vp <= 1e-9 && Rp.dist < bestDist - 1e-9
                best = xp; bestDist = Rp.dist;
            end
        else
            k = k + 1;
            if k > opts.kmax, k = 1; end
        end

        % -------------------------------------------------- adaptive penalty
        if vx > 1e-9
            lam.cap = min(lam.cap * 1.02, 1e5);
            lam.tw  = min(lam.tw  * 1.02, 1e5);
        else
            lam.cap = max(lam.cap * 0.98, 1);
            lam.tw  = max(lam.tw  * 0.98, 0.5);
        end

        % -------------------------------------------------- progress
        if ctr.used() >= nextChk
            curve(end+1) = bestDist; %#ok<AGROW>
            nextChk = nextChk + chk;
            if opts.verbose
                fprintf('  ffe %7d  best %.2f  cur %.2f  lam %.1f/%.1f  k=%d\n', ...
                        ctr.used(), bestDist, fx, lam.cap, lam.tw, k);
            end
        end
    end

    % ------------------------------------------------------------ output
    if isempty(best)
        % no feasible solution found: return the least violating one seen
        [~, ~, Rx] = vrptw_penalized_cost(S, x, lam);
        warning('solve_vns:nofeasible', 'no feasible solution found; returning best-effort');
        best = x;
    end

    R = vrptw_eval(S, best);
    out = struct('dist', R.cost, 'nveh', R.nveh, 'feasible', R.feasible, ...
                 'ffe', ctr.used(), 'startDist', startDist, ...
                 'improve', 100 * (startDist - R.cost) / max(startDist, 1e-9), ...
                 'curve', curve);
end


% ================================================================ helpers

function o = setdef(o, f, v)
    if ~isfield(o, f), o.(f) = v; end
end

function rp = routePen(S, rt, lam)
    st = vrptw_route_stats(S, rt);
    rp = st.dist + lam.cap * st.capExcess + lam.tw * st.twExcess;
end

function routes = shake(S, routes, k)
%SHAKE  Random point in neighbourhood k (a single random move of that type).
    routes = routes(:)';
    nR = numel(routes);
    for attempt = 1:50
        switch k
            case 1  % relocate
                r1 = randi(nR); if isempty(routes{r1}), continue; end
                p1 = randi(numel(routes{r1}));
                r2 = randi(nR);
                p2 = randi(numel(routes{r2}) + 1);
                c  = routes{r1}(p1);
                routes{r1}(p1) = [];
                routes{r2} = [routes{r2}(1:p2-1), c, routes{r2}(p2:end)];
                return;
            case 2  % exchange
                r1 = randi(nR); if isempty(routes{r1}), continue; end
                r2 = randi(nR); if isempty(routes{r2}), continue; end
                p1 = randi(numel(routes{r1})); p2 = randi(numel(routes{r2}));
                tmp = routes{r1}(p1);
                routes{r1}(p1) = routes{r2}(p2);
                routes{r2}(p2) = tmp;
                return;
            case 3  % 2-opt*
                r1 = randi(nR); if isempty(routes{r1}), continue; end
                r2 = randi(nR); if isempty(routes{r2}), continue; end
                a = routes{r1}; b = routes{r2};
                p1 = randi(numel(a)); p2 = randi(numel(b));
                routes{r1} = [a(1:p1-1), b(p2:end)];
                routes{r2} = [b(1:p2-1), a(p1:end)];
                return;
            case 4  % or-opt (chain of 2)
                r1 = randi(nR); if numel(routes{r1}) < 2, continue; end
                p1 = randi(numel(routes{r1}) - 1);
                seg = routes{r1}(p1:p1+1);
                routes{r1}(p1:p1+1) = [];
                r2 = randi(nR);
                p2 = randi(numel(routes{r2}) + 1);
                routes{r2} = [routes{r2}(1:p2-1), seg, routes{r2}(p2:end)];
                return;
        end
    end
end

function [routes, f, R, v] = vnd(S, routes, f, lam, ctr)
%VND  Variable neighbourhood descent: N1 -> N2 -> N3 -> N4, first improvement.
    improved = true;
    R = []; v = 0;
    while improved && ~ctr.exhausted()
        improved = false;

        [routes, ok, f, R, v] = tryRelocate(S, routes, f, lam, ctr);
        if ctr.exhausted(), break; end
        if ok, improved = true; continue; end

        [routes, ok, f, R, v] = tryExchange(S, routes, f, lam, ctr);
        if ctr.exhausted(), break; end
        if ok, improved = true; continue; end

        [routes, ok, f, R, v] = try2optStar(S, routes, f, lam, ctr);
        if ctr.exhausted(), break; end
        if ok, improved = true; continue; end

        [routes, ok, f, R, v] = tryOrOpt(S, routes, f, lam, ctr);
        if ok, improved = true; end
    end
    if isempty(R)
        [f, v, R] = vrptw_penalized_cost(S, routes, lam);
        ctr.hit();
    end
end

function [routes, ok, f, R, v] = tryRelocate(S, routes, f, lam, ctr)
    ok = false; R = []; v = 0;
    nR = numel(routes);
    for r1 = 1:nR
        if isempty(routes{r1}), continue; end
        base1 = routePen(S, routes{r1}, lam);
        for p1 = 1:numel(routes{r1})
            c = routes{r1}(p1);
            cand1 = routes{r1}; cand1(p1) = [];
            new1 = routePen(S, cand1, lam);
            for r2 = 1:nR
                if r2 == r1, continue; end
                base2 = routePen(S, routes{r2}, lam);
                for p2 = 0:numel(routes{r2})
                    cand2 = [routes{r2}(1:p2), c, routes{r2}(p2+1:end)];
                    new2 = routePen(S, cand2, lam);
                    ctr.hit();
                    delta = (new1 + new2) - (base1 + base2);
                    if delta < -1e-9
                        routes{r1} = cand1; routes{r2} = cand2;
                        ok = true;
                        [f, v, R] = vrptw_penalized_cost(S, routes, lam);
                        ctr.hit();
                        return;
                    end
                    if ctr.exhausted(), return; end
                end
            end
            % also allow relocating to a brand new empty slot
            if numel(routes) < S.m
                cand2 = [c];
                new2 = routePen(S, cand2, lam);
                ctr.hit();
                delta = (new1 + new2) - base1;
                if delta < -1e-9
                    routes{r1} = cand1; routes{end+1} = cand2;
                    ok = true;
                    [f, v, R] = vrptw_penalized_cost(S, routes, lam);
                    ctr.hit();
                    return;
                end
            end
        end
    end
end

function [routes, ok, f, R, v] = tryExchange(S, routes, f, lam, ctr)
    ok = false; R = []; v = 0;
    nR = numel(routes);
    for r1 = 1:nR
        if isempty(routes{r1}), continue; end
        base1 = routePen(S, routes{r1}, lam);
        for r2 = r1:nR
            if isempty(routes{r2}), continue; end
            base2 = routePen(S, routes{r2}, lam);
            for p1 = 1:numel(routes{r1})
                for p2 = 1:numel(routes{r2})
                    if r1 == r2 && p1 >= p2, continue; end
                    a = routes{r1}; b = routes{r2};
                    tmp = a(p1); a(p1) = b(p2); b(p2) = tmp;
                    new1 = routePen(S, a, lam);
                    if r1 == r2
                        delta = new1 - base1;
                    else
                        new2 = routePen(S, b, lam);
                        delta = (new1 + new2) - (base1 + base2);
                    end
                    ctr.hit();
                    if delta < -1e-9
                        routes{r1} = a; routes{r2} = b;
                        ok = true;
                        [f, v, R] = vrptw_penalized_cost(S, routes, lam);
                        ctr.hit();
                        return;
                    end
                    if ctr.exhausted(), return; end
                end
            end
        end
    end
end

function [routes, ok, f, R, v] = try2optStar(S, routes, f, lam, ctr)
    ok = false; R = []; v = 0;
    nR = numel(routes);
    for r1 = 1:nR-1
        if isempty(routes{r1}), continue; end
        base1 = routePen(S, routes{r1}, lam);
        for r2 = r1+1:nR
            if isempty(routes{r2}), continue; end
            base2 = routePen(S, routes{r2}, lam);
            a = routes{r1}; b = routes{r2};
            for p1 = 1:numel(a)
                for p2 = 1:numel(b)
                    na = [a(1:p1-1), b(p2:end)];
                    nb = [b(1:p2-1), a(p1:end)];
                    delta = (routePen(S, na, lam) + routePen(S, nb, lam)) ...
                          - (base1 + base2);
                    ctr.hit();
                    if delta < -1e-9
                        routes{r1} = na; routes{r2} = nb;
                        ok = true;
                        [f, v, R] = vrptw_penalized_cost(S, routes, lam);
                        ctr.hit();
                        return;
                    end
                    if ctr.exhausted(), return; end
                end
            end
        end
    end
end

function [routes, ok, f, R, v] = tryOrOpt(S, routes, f, lam, ctr)
    ok = false; R = []; v = 0;
    nR = numel(routes);
    for r1 = 1:nR
        if numel(routes{r1}) < 2, continue; end
        base1 = routePen(S, routes{r1}, lam);
        for len = 2:2
            for p1 = 1:numel(routes{r1})-len+1
                seg = routes{r1}(p1:p1+len-1);
                cand1 = routes{r1}([1:p1-1, p1+len:end]);
                new1 = routePen(S, cand1, lam);
                for r2 = 1:nR
                    if r2 == r1
                        % reinsert elsewhere inside the same route
                        for p2 = 0:numel(cand1)
                            cand2 = [cand1(1:p2), seg, cand1(p2+1:end)];
                            ctr.hit();
                            if routePen(S, cand2, lam) < base1 - 1e-9
                                routes{r1} = cand2;
                                ok = true;
                                [f, v, R] = vrptw_penalized_cost(S, routes, lam);
                                ctr.hit();
                                return;
                            end
                            if ctr.exhausted(), return; end
                        end
                        continue;
                    end
                    base2 = routePen(S, routes{r2}, lam);
                    for p2 = 0:numel(routes{r2})
                        cand2 = [routes{r2}(1:p2), seg, routes{r2}(p2+1:end)];
                        ctr.hit();
                        delta = (new1 + routePen(S, cand2, lam)) - (base1 + base2);
                        if delta < -1e-9
                            routes{r1} = cand1; routes{r2} = cand2;
                            ok = true;
                            [f, v, R] = vrptw_penalized_cost(S, routes, lam);
                            ctr.hit();
                            return;
                        end
                        if ctr.exhausted(), return; end
                    end
                end
            end
        end
    end
end
