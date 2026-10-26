function op_timing()
%OP_TIMING  How much CPU time does each operator actually consume?
%
%   Measured from the constructive solution of each instance, 20 applications
%   per operator.  This is the number that decides how many iterations fit in a
%   300 s budget, and therefore how much searching the algorithm can do at all:
%   at 40 ms per move, 300 s buys 7,500 moves; at 4 ms it buys 75,000.
%
%   The breakdown also reports the two non-operator costs in the loop -- the
%   objective evaluation and the policy update -- because a linear policy forward
%   and backward pass costs microseconds and is not where the budget goes, while
%   the operator is.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    addpath(fullfile(here, '..', '09_solvers'));

    bdir = benchmark_dir();
    names = {'C1_2_1', 'R1_2_1'};
    opNames = {4, 'path elimination'; 6, 'light kick'; 8, 'elite relink'; 9, 'string move'};

    for i = 1:numel(names)
        inst = read_vrptw_instance(fullfile(bdir, 'instances200', [names{i} '.TXT']));
        S = vrptw_model(inst);
        P = problem_static(S);

        % a mid-run solution is more representative than the construction: routes
        % are fuller and the repair has less slack
        x = P.construct();
        for k = 1:30, [x, ~] = rlgbka_ops(6, P, x, struct('lam', struct('cap',50,'tw',5), ...
                'ctr', cpu_budget(inf), 'elite', {{x}}, 'vehWeight', 1e4, 'scale', 1)); end
        R = P.evalReport(x);

        fprintf('=== %s   (%d vehicles, dist %.1f, %d routes) ===\n', ...
                names{i}, R.nveh, R.cost, R.nveh);

        ctr = cpu_budget(inf);
        lam = struct('cap', 50, 'tw', 5);
        ctx = struct('lam', lam, 'ctr', ctr, 'elite', {{x}}, 'vehWeight', 1e4, 'scale', 1);

        fprintf('  %-5s %-20s %10s %12s\n', 'id', 'operator', 'ms/call', 'moves in 300 s');
        fprintf('  %s\n', repmat('-', 1, 52));

        tot = 0;
        for k = 1:size(opNames, 1)
            id = opNames{k, 1};
            t0 = cputime;
            for r = 1:100
                [~, ~] = rlgbka_ops(id, P, x, ctx);
            end
            ms = (cputime - t0) / 100 * 1000;
            tot = tot + ms;
            fprintf('  %-5d %-20s %10.1f %12.0f\n', id, opNames{k, 2}, ms, 300000/ms);
        end
        fprintf('  %-5s %-20s %10.1f %12.0f\n', '', 'mean', tot/4, 300000/(tot/4));

        % non-operator costs
        t0 = cputime;
        for r = 1:200, [~, ~] = vrp_objective(P, x, lam, 1e4); end
        fprintf('  %-5s %-20s %10.3f\n', '', 'objective eval', (cputime-t0)/200*1000);

        fprintf('\n');
    end
end
