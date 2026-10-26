function test_pool_sp()
%TEST_POOL_SP  Does set-partitioning recombination improve on the search?
%
%   Runs the search normally, collects the routes it visits, then recombines them
%   by set partitioning and reports both solutions.  One configuration, one seed,
%   300 CPU seconds of search, on R1_2_1 -- the instance where the search is
%   furthest from the best known solution.
%
%   The collection samples the current solution every SAMPLE iterations rather
%   than every iteration: at 24,000 iterations and 22 routes, collecting every
%   time means half a million inserts and the bookkeeping would cost more than the
%   search it is meant to improve.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    addpath(fullfile(here, '..', '09_solvers'));

    bdir = benchmark_dir();
    inst = read_vrptw_instance(fullfile(bdir, 'instances200', 'R1_2_1.TXT'));
    S = vrptw_model(inst);
    P = problem_static(S);

    VEHW = 1e4; BKS_V = 20; BKS_D = 4784.11;
    SAMPLE = 1;

    % ---- stage 1: the search, with pool collection bolted on
    adapter = @(id, Pp, r, ctx) rlgbka_ops2(id, Pp, r, ...
                    struct('lam', ctx.lam, 'scale', ctx.scale));
    o = struct('timeLimit', 300, 'seed', 1, 'verbose', false, ...
               'opSet', [3 5 2], 'opFun', adapter, 'mode', 'roundrobin');

    fprintf('stage 1: search with pool collection (300 s)\n');
    [best, out] = solve_rlgbka_online_collect(P, o, SAMPLE);

    R = P.evalReport(best);
    fprintf('  search result: %d / %.2f  (gap %.2f%%)  iters %d  pool %d\n\n', ...
            R.nveh, R.cost, 100*(R.cost-BKS_D)/BKS_D, out.iter, numel(out.pool));

    % ---- stage 2: recombination
    fprintf('stage 2: set partitioning over the pool\n');
    [spRoutes, info] = pool_recombine(P, out.pool, VEHW, 120);

    fprintf('  routes in pool      %d\n', info.m);
    fprintf('  build matrix        %.1f s\n', info.tBuild);
    fprintf('  solve               %.1f s   (exitflag %d)\n', info.tSolve, info.exitflag);
    fprintf('  routes used         %d\n', info.usedRoutes);

    if info.ok
        Rsp = P.evalReport(spRoutes);
        served = 0;
        for k = 1:numel(spRoutes), served = served + numel(spRoutes{k}); end
        fprintf('  recombination: %d / %.2f  (gap %.2f%%)  customers %d\n\n', ...
                Rsp.nveh, Rsp.cost, 100*(Rsp.cost-BKS_D)/BKS_D, served);

        if Rsp.feasible && served == P.n && ...
           (Rsp.nveh < R.nveh || (Rsp.nveh == R.nveh && Rsp.cost < R.cost - 1e-6))
            fprintf('VERDICT: recombination IMPROVED the solution: %.2f -> %.2f\n', ...
                    R.cost, Rsp.cost);
        else
            fprintf('VERDICT: recombination did NOT improve (%.2f vs %.2f)\n', ...
                    Rsp.cost, R.cost);
        end
    else
        fprintf('  recombination failed, keeping the search result\n');
    end
end
