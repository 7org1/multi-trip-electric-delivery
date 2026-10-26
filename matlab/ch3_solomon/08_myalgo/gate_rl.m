function gate_rl()
%GATE_RL  Is there any room left for a learned scheduler?
%
%   The argument needs no training, only an upper bound.
%
%       No policy -- learned or not -- can beat the best-known solution.
%       Therefore   max gain from RL  <=  gap left by a FIXED schedule.
%
%   So run one fixed operator set on one instance per class and look at the
%   remaining gap.  If most classes are already at the best-known value, the
%   ceiling for any scheduling policy is zero and RL has nothing to learn.
%
%   WHAT THIS TEST CAN AND CANNOT DO
%       small gap  -> RL is definitely unnecessary   (strong conclusion)
%       large gap  -> RL MIGHT help; the gap could equally come from a missing
%                     operator rather than from bad scheduling.  This test can
%                     only falsify, never confirm, so it decides whether to keep
%                     going, not what to publish.
%
%   FIXED CONFIGURATION
%       operators [8 2 6] = elite relinking + related removal + light kick
%       This is the set that reached the exact best-known value on c1_2_1.
%       Selection is random over the three, i.e. a fixed stochastic schedule
%       with no state dependence at all.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    bdir = benchmark_dir();
    ops  = [8 2 6];
    BUDGET = 1000;
    SEED   = 1;

    names = {'C1_2_1','C2_2_1','R1_2_1','R2_2_1','RC1_2_1','RC2_2_1'};
    bks = load_bks(fullfile(bdir, 'gh200_bks.csv'));

    fprintf('fixed operator set [8 2 6], random selection, budget %d, seed %d\n', ...
            BUDGET, SEED);
    fprintf('no learning of any kind\n\n');
    fprintf('%-9s %6s %6s %10s %10s %8s\n', ...
            'instance', 'veh', 'bksVeh', 'dist', 'bksDist', 'gap%');
    fprintf('%s\n', repmat('-', 1, 58));

    gaps = []; vehOK = [];
    for i = 1:numel(names)
        inst = read_vrptw_instance(fullfile(bdir, 'instances200', [names{i} '.TXT']));
        S = vrptw_model(inst);
        P = problem_static(S);

        opts = struct('budget', BUDGET, 'seed', SEED, 'opSet', ops, ...
                      'decideEvery', 20, 'record', false, 'verbose', false);
        [~, out] = solve_rlgbka(P, opts);

        key = matlab.lang.makeValidName(lower(inst.name));
        b = bks.(key);

        if out.nveh > b.routes
            gap = NaN;                  % not comparable: too many vehicles
            vehOK(end+1) = false;       %#ok<AGROW>
        else
            gap = 100 * (out.dist - b.dist) / b.dist;
            vehOK(end+1) = true;
        end
        gaps(end+1) = gap;              %#ok<AGROW>

        if isnan(gap)
            fprintf('%-9s %6d %6d %10.2f %10.2f %8s\n', ...
                    lower(inst.name), out.nveh, b.routes, out.dist, b.dist, 'n/a');
        else
            fprintf('%-9s %6d %6d %10.2f %10.2f %8.2f\n', ...
                    lower(inst.name), out.nveh, b.routes, out.dist, b.dist, gap);
        end
    end

    g = gaps(~isnan(gaps));
    fprintf('\n=== verdict ===\n');
    fprintf('  reached the best-known fleet size : %d / %d\n', sum(vehOK), numel(names));
    if isempty(g)
        fprintf('  no comparable gaps\n');
        return;
    end
    fprintf('  gap  min %.2f%%  median %.2f%%  max %.2f%%\n', ...
            min(g), median(g), max(g));
    fprintf('  instances within 1%% of best known : %d / %d\n', sum(g <= 1), numel(g));

    fprintf('\n');
    if median(g) <= 1
        fprintf('  A fixed, non-learned schedule already sits on the best known\n');
        fprintf('  value.  The ceiling for ANY scheduler, including RL, is about\n');
        fprintf('  %.1f percentage points.  RL is not worth pursuing here.\n', median(g));
    elseif median(g) <= 3
        fprintf('  Small room remains.  Before any training, check whether a\n');
        fprintf('  different fixed schedule closes it -- if one does, RL is still\n');
        fprintf('  unnecessary.\n');
    else
        fprintf('  Substantial room remains, but that alone does not justify RL:\n');
        fprintf('  the gap may come from a missing operator rather than from bad\n');
        fprintf('  scheduling.  Probe the operator library first.\n');
    end
end
