function diag_budget()
%DIAG_BUDGET  Is the fleet gap a budget problem or a capability problem?
%
%   The solver currently runs 1,000 iterations.  Published VRPTW methods run
%   10^5 to 10^6 evaluations, so before concluding that the operator library
%   cannot reach the best-known fleet count, give it more budget and see whether
%   the count moves.
%
%     count approaches the best known with budget -> budget problem
%     count stays put while budget grows          -> capability problem, and the
%                                                    fix is a stronger operator
%                                                    (ejection chains), not a
%                                                    scheduler

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    bdir = benchmark_dir();
    bks  = load_bks(fullfile(bdir, 'gh200_bks.csv'));

    names   = {'R1_2_1', 'C2_2_1'};
    budgets = [1000 3000 8000];
    ops     = [8 2 6];

    fprintf('operator set [8 2 6], random selection, seed 1\n\n');

    for i = 1:numel(names)
        inst = read_vrptw_instance(fullfile(bdir, 'instances200', [names{i} '.TXT']));
        S = vrptw_model(inst);
        P = problem_static(S);
        b = bks.(matlab.lang.makeValidName(lower(inst.name)));

        fprintf('%s   best known: %d vehicles, %.2f\n', ...
                lower(inst.name), b.routes, b.dist);
        fprintf('  %8s %6s %10s %9s %8s\n', 'budget', 'veh', 'dist', 'gap%', 'time');

        for bd = budgets
            opts = struct('budget', bd, 'seed', 1, 'opSet', ops, ...
                          'decideEvery', 20, 'record', false, 'verbose', false);
            t0 = tic;
            [~, out] = solve_rlgbka(P, opts);
            el = toc(t0);
            if out.nveh > b.routes
                fprintf('  %8d %6d %10.2f %9s %8.0f\n', bd, out.nveh, out.dist, 'n/a', el);
            else
                gap = 100 * (out.dist - b.dist) / b.dist;
                fprintf('  %8d %6d %10.2f %9.2f %8.0f\n', bd, out.nveh, out.dist, gap, el);
            end
        end
        fprintf('\n');
    end
end
