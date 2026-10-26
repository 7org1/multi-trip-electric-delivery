function test_vns()
%TEST_VNS  Smoke-test the penalised framework and the VNS on one instance.
%
% Checks, in order:
%   1. the violation magnitudes are right (a deliberately overloaded route)
%   2. the penalised cost equals distance when there is no violation
%   3. VNS runs, spends its budget, and returns something feasible
%   4. how much it improves the construction

    here = fileparts(mfilename('fullpath'));
    addpath(here);

    inst = read_vrptw_instance(fullfile(benchmark_dir(), 'instances200', 'C1_2_1.TXT'));
    S = vrptw_model(inst);

    lam = struct('cap', 50, 'tw', 5);

    fprintf('=== 1. violation magnitudes ===\n');
    big = 2:21;                      % 20 customers, way over capacity
    st = vrptw_route_stats(S, big);
    fprintf('  load %g / Q %g  capExcess %g  twExcess %.1f  feasible %d\n', ...
            st.load, S.Q, st.capExcess, st.twExcess, st.feasible);
    assert(abs(st.capExcess - max(0, st.load - S.Q)) < 1e-9, 'capacity excess wrong');
    fprintf('  PASS\n\n');

    fprintf('=== 2. penalised cost equals distance when feasible ===\n');
    routes = vrptw_construct(S);
    [f, v, R] = vrptw_penalized_cost(S, routes, lam);
    fprintf('  dist %.2f, violation %.2f, f-dist = %.2f\n', R.dist, v, f - R.dist);
    if R.feasible
        assert(abs(f - R.dist) < 1e-9, 'penalised cost should equal distance when feasible');
        fprintf('  PASS\n');
    else
        fprintf('  construction is infeasible under this fleet; penalty is active\n');
    end
    fprintf('\n');

    fprintf('=== 3. VNS run ===\n');
    S.m = 20;                        % fix the fleet to the best-known count
    opts = struct('budget', 30000, 'seed', 1, 'verbose', false);
    tic; [best, out] = solve_vns(S, opts); el = toc;
    fprintf('  budget %d, used %d, %.1f s\n', opts.budget, out.ffe, el);
    fprintf('  result: %d vehicles, dist %.2f, feasible %d\n', ...
            out.nveh, out.dist, out.feasible);
    fprintf('  construction was %.2f -> improvement %.1f%%\n', ...
            out.startDist, out.improve);
    fprintf('  curve: %s\n', mat2str(round(out.curve)));
    fprintf('\n  BKS for C1_2_1: 20 vehicles, 2704.57\n');
    if out.feasible
        fprintf('  gap vs BKS: %.2f%%\n', 100 * (out.dist - 2704.57) / 2704.57);
    end
end
