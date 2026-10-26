function test_rlgbka()
%TEST_RLGBKA  Smoke-test the fifth algorithm on one benchmark instance.
%
% Checks the pieces that can be wrong silently:
%   1. the adapter exposes what the solver expects
%   2. operator 4 (route elimination) can actually remove a route
%   3. the solver runs, spends its budget, and returns something feasible
%   4. how it compares with the construction and with the best known solution

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    inst = read_vrptw_instance(fullfile(benchmark_dir(), 'instances200', 'C1_2_1.TXT'));
    S = vrptw_model(inst);
    P = problem_static(S);

    fprintf('=== 1. adapter ===\n');
    fprintf('  n %d, N %d, m %g, Q %g, timeDependent %d\n', ...
            P.n, P.N, P.m, P.Q, P.timeDependent);
    r0 = P.construct();
    [f0, v0, R0] = P.eval(r0, struct('cap', 50, 'tw', 5));
    fprintf('  construction: %d routes, dist %.2f, feasible %d\n\n', ...
            R0.nveh, R0.dist, R0.feasible);

    fprintf('=== 2. operator 4, route elimination ===\n');
    ctx = struct('lam', struct('cap', 50, 'tw', 5), 'ctr', ffe_budget(inf), ...
                 'elite', {{}}, 'vehWeight', 1000);
    nEl = 0; capX = []; twX = [];
    for t = 1:20
        [r4, aux] = rlgbka_ops(4, P, r0, ctx);
        if aux.eliminated
            nEl = nEl + 1;
            [~, ~, R4] = P.eval(r4, struct('cap', 50, 'tw', 5));
            capX(end+1) = R4.capExcess; %#ok<AGROW>
            twX(end+1)  = R4.twExcess;  %#ok<AGROW>
        end
    end
    fprintf('  succeeded in %d / 20 applications\n', nEl);
    if nEl > 0
        fprintf('  violation after elimination: cap mean %.1f, tw mean %.1f (max %.1f)\n', ...
                mean(capX), mean(twX), max(twX));
        fprintf('  (a small tw excess means local repair can finish the job;\n');
        fprintf('   a huge one means the 20-route solution is far from feasible)\n');
    end
    fprintf('\n');

    fprintf('=== 3. all eight operators run without error ===\n');
    for id = 1:8
        ctx2 = ctx; ctx2.elite = {r0};
        try
            [rr, aux] = rlgbka_ops(id, P, r0, ctx2);
            R = P.evalReport(rr);
            fprintf('  op %d: %d routes, dist %.1f, feasible %d, repaired %d\n', ...
                    id, R.nveh, R.cost, R.feasible, aux.repaired);
        catch ME
            fprintf('  op %d: ERROR %s\n', id, ME.message);
        end
    end
    fprintf('\n');

    fprintf('=== 4. solver run ===\n');
    opts = struct('budget', 40000, 'seed', 1, 'verbose', false);
    tic; [best, out] = solve_rlgbka(P, opts); el = toc;
    fprintf('  %.1f s, %d ffe, %d iterations\n', el, out.ffe, out.iter);
    fprintf('  result: %d routes, dist %.2f, feasible %d\n', ...
            out.nveh, out.dist, out.feasible);
    fprintf('  construction %d routes / %.2f -> improvement %.1f%%\n', ...
            R0.nveh, R0.dist, out.improve);
    fprintf('  operator use:  %s\n', mat2str(out.opUse));
    fprintf('  operator wins: %s\n', mat2str(out.opSucc));
    fprintf('  curve: %s\n', mat2str(round(out.curve)));
    fprintf('\n  BKS: 20 routes, 2704.57\n');
    if out.feasible
        fprintf('  gap vs BKS: %.2f%%\n', 100 * (out.dist - 2704.57) / 2704.57);
    end
end
