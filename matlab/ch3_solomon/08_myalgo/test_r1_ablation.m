function test_r1_ablation()
%TEST_R1_ABLATION  Does the policy-controlled operator scale help on the hardest instance?
%
%   R1_2_1 has time-window width 10, the tightest of the six classes, and every
%   baseline stalls at 22 vehicles against a best known of 20.  It is the case
%   where the search has the least room, so it is the honest place to test
%   whether letting the policy choose how far an operator reaches is worth
%   anything.
%
%   Two configurations, identical in every other respect:
%       fixed    the operator scale is 1 -- the operator runs at its default size
%       learned  a second policy head chooses x0.5 / x1 / x2 for every move
%
%   If the learned head does not beat the fixed one across seeds, the coupling is
%   decoration and should be dropped.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    addpath(fullfile(here, '..', '09_solvers'));

    bdir = benchmark_dir();
    inst = read_vrptw_instance(fullfile(bdir, 'instances200', 'R1_2_1.TXT'));
    S = vrptw_model(inst);
    P = problem_static(S);

    BKS_VEH = 20; BKS_DIST = 4784.11;
    SEEDS = 1:3;
    OPTS = struct('timeLimit', 300, 'verbose', false, 'opSet', [4 6 8 9]);

    cases = { 'fixed',   false
              'learned', true };

    fprintf('R1_2_1   best known %d / %.2f   (ALNS 22 / 4935.9)\n\n', BKS_VEH, BKS_DIST);

    R = struct('name', {}, 'veh', {}, 'dist', {}, 'gap', {}, 'iter', {}, 'wins', {});

    for c = 1:size(cases, 1)
        name = cases{c, 1};
        useScale = cases{c, 2};
        fprintf('--- %s ---\n', name);

        vs = []; ds = []; its = []; ws = [];
        for sd = SEEDS
            o = OPTS;
            o.seed = sd;
            o.useScaleHead = useScale;
            [~, out] = solve_rlgbka_online(P, o);
            gap = 100 * (out.dist - BKS_DIST) / BKS_DIST;
            fprintf('  seed %d: %d / %8.2f  gap %6.2f%%  iters %7d  wins %4d\n', ...
                    sd, out.nveh, out.dist, gap, out.iter, sum(out.opSucc));
            vs(end+1) = out.nveh;   %#ok<AGROW>
            ds(end+1) = out.dist;   %#ok<AGROW>
            its(end+1) = out.iter;  %#ok<AGROW>
            ws(end+1) = sum(out.opSucc); %#ok<AGROW>
        end

        R(end+1) = struct('name', name, 'veh', mean(vs), 'dist', mean(ds), ...
                          'gap', mean(100*(ds-BKS_DIST)/BKS_DIST), ...
                          'iter', mean(its), 'wins', mean(ws)); %#ok<AGROW>
        fprintf('\n');
    end

    fprintf('=== summary over %d seeds ===\n', numel(SEEDS));
    fprintf('%-9s %6s %12s %9s %10s %8s\n', 'config', 'veh', 'dist', 'gap%', 'iters', 'wins');
    fprintf('%s\n', repmat('-', 1, 60));
    for i = 1:numel(R)
        fprintf('%-9s %6.2f %12.2f %9.2f %10.0f %8.1f\n', ...
                R(i).name, R(i).veh, R(i).dist, R(i).gap, R(i).iter, R(i).wins);
    end

    dGap = R(1).gap - R(2).gap;   % fixed minus learned; positive means learned is better
    fprintf('\nlearned minus fixed: gap %+.2f points, iterations %+.0f%%\n', ...
            -dGap, 100 * (R(2).iter - R(1).iter) / max(R(1).iter, 1));
    if dGap > 1
        fprintf('VERDICT: the scale head helps materially.\n');
    elseif dGap > 0.3
        fprintf('VERDICT: small but consistent gain.\n');
    else
        fprintf('VERDICT: no useful gain -- the coupling is decoration.\n');
    end
end
