function [bestRoutes, info] = pool_recombine(P, pool, vehW, timeLimit)
%POOL_RECOMBINE  Recombine the routes seen during the search by set partitioning.
%
%   [bestRoutes, info] = pool_recombine(P, pool, vehW, timeLimit)
%
%   pool  cell array of routes, each a row vector of customer ids
%   vehW  vehicle weight, so that minimising the objective first minimises the
%         number of routes used
%
%   WHY THIS CAN BEAT THE SEARCH THAT PRODUCED THE POOL
%   A local search follows one trajectory: it can only improve the solution it
%   currently holds, so it can never simultaneously use the route produced at
%   iteration 3 and the route produced at iteration 800 -- they were never in the
%   same solution.  Set partitioning looks at every route the search ever visited
%   and chooses the best cover of all customers from them, including combinations
%   that never coexisted.  That is a strictly larger neighbourhood than anything a
%   destroy-and-repair move can express.
%
%   THE MODEL
%       min  sum_r (dist_r + vehW) x_r
%       s.t. A x = 1        each customer covered exactly once
%            x in {0,1}^m
%   A is sparse with one row per customer and one column per route.
%
%   FEASIBILITY IS GUARANTEED BY CONSTRUCTION
%   The routes of the incumbent solution are in the pool, so a cover always
%   exists; the solver can never return an infeasible partitioning, and it can
%   never return something worse than the incumbent either, because the incumbent
%   is one of the feasible 0/1 points.

    info = struct('m', 0, 'tBuild', 0, 'tSolve', 0, 'exitflag', NaN, ...
                  'obj', NaN, 'usedRoutes', 0, 'ok', false);

    n = P.n;
    idOffset = min(cellfun(@(r) min(r), pool)) - 1;   % customers are 2..n+1
    if idOffset < 0, idOffset = 0; end

    m = numel(pool);
    info.m = m;

    t0 = cputime;

    % ---- sparse incidence matrix, one column per route
    nnzTotal = 0;
    for r = 1:m, nnzTotal = nnzTotal + numel(pool{r}); end
    rows = zeros(nnzTotal, 1); cols = zeros(nnzTotal, 1);
    k = 0;
    for r = 1:m
        rt = pool{r};
        for j = 1:numel(rt)
            k = k + 1;
            rows(k) = rt(j) - idOffset;
            cols(k) = r;
        end
    end
    A = sparse(rows, cols, 1, n, m);
    info.tBuild = cputime - t0;

    % ---- objective: distance plus the vehicle weight
    f = zeros(m, 1);
    for r = 1:m
        st = P.stats(pool{r});
        f(r) = st.dist + vehW;
    end

    % ---- solve
    opts = optimoptions('intlinprog', 'Display', 'off', ...
                        'MaxTime', max(10, timeLimit), ...
                        'RelativeGapTolerance', 1e-4);

    t0 = cputime;
    [x, ~, exitflag] = intlinprog(f, 1:m, [], [], A, ones(n, 1), ...
                                  zeros(m, 1), ones(m, 1), opts);
    info.tSolve = cputime - t0;
    info.exitflag = exitflag;

    if isempty(x)
        info.ok = false;
        bestRoutes = {};
        return;
    end

    sel = find(x > 0.5);
    info.usedRoutes = numel(sel);
    info.obj = sum(f(sel));
    bestRoutes = pool(sel);
    info.ok = true;
end
