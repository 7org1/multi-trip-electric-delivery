function diag_vehweight()
%DIAG_VEHWEIGHT  Is the fleet weight simply too small for the harder classes?
%
%   The solver minimises   distance + W * nveh + penalty.  Merging two routes
%   saves W but adds distance.  On the clustered C1 class the added distance is
%   small, so W = 1000 dominates and the fleet reaches the best-known count.  On
%   the random classes with tight windows, merging can add well over 1000 of
%   distance, so the search rationally refuses to merge -- and the reported
%   vehicle count stays above the best known.
%
%   If raising W fixes the fleet count on R1, the problem was never the operator
%   library or the scheduler: it was one constant.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    bdir = benchmark_dir();
    bks  = load_bks(fullfile(bdir, 'gh200_bks.csv'));

    names = {'R1_2_1', 'RC1_2_1', 'C2_2_1'};
    Ws    = [1000 10000 100000];
    ops   = [8 2 6];

    fprintf('operator set [8 2 6], random selection, budget 1000, seed 1\n\n');

    for i = 1:numel(names)
        inst = read_vrptw_instance(fullfile(bdir, 'instances200', [names{i} '.TXT']));
        S = vrptw_model(inst);
        P = problem_static(S);
        b = bks.(matlab.lang.makeValidName(lower(inst.name)));

        fprintf('%s   best known: %d vehicles, %.2f\n', ...
                lower(inst.name), b.routes, b.dist);
        fprintf('  %10s %6s %10s %9s\n', 'vehWeight', 'veh', 'dist', 'gap%');

        for w = Ws
            opts = struct('budget', 1000, 'seed', 1, 'opSet', ops, ...
                          'vehWeight', w, 'decideEvery', 20, ...
                          'record', false, 'verbose', false);
            [~, out] = solve_rlgbka(P, opts);
            if out.nveh > b.routes
                tag = 'n/a (more vehicles)';
                fprintf('  %10d %6d %10.2f   %s\n', w, out.nveh, out.dist, tag);
            else
                gap = 100 * (out.dist - b.dist) / b.dist;
                fprintf('  %10d %6d %10.2f %9.2f\n', w, out.nveh, out.dist, gap);
            end
        end
        fprintf('\n');
    end
end
