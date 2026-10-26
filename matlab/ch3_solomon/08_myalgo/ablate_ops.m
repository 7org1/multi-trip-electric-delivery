function ablate_ops()
%ABLATE_OPS  Leave-one-out ablation over the operator portfolio.
%
%   Question: which operators actually carry the search, and which can be
%   deleted without losing the result?
%
%   DECISION RULE IS LEXICOGRAPHIC
%   The benchmark ranks solutions by (vehicles, distance).  A configuration that
%   cannot reach the best fleet size loses outright, however short its routes
%   are, so the vehicle column is read first.
%
%   WHAT ONE BUDGET UNIT MEANS NOW
%   One iteration = one complete evaluation of a candidate solution.  Internal
%   insertion checks are NOT counted.  An earlier version did count them, and a
%   single large-removal call could consume the entire budget, which made the
%   comparison meaningless: the run stopped at the construction solution.
%
%   THE POLICY IS UNTRAINED HERE ON PURPOSE
%   This measures the operator library, not the scheduler.  A trained policy's
%   contribution is a separate experiment.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    bdir = benchmark_dir();
    instName = 'C1_2_1';
    inst = read_vrptw_instance(fullfile(bdir, 'instances200', [instName '.TXT']));
    S = vrptw_model(inst);
    P = problem_static(S);

    BKS_VEH = 20; BKS_DIST = 2704.57;
    BUDGET  = 1000;
    SEEDS   = 1:2;

    % operator ids: 1 far, 2 related, 3 large-random, 4 route-elim,
    %               5 worst, 6 greedy-kick, 7 regret-kick, 8 elite-relink
    cfg = {
        'full 8',            1:8
        'four',              [8 4 2 6]
        'drop O1 relink',    [4 2 6]
        'drop O2 route',     [8 2 6]
        'drop O3 related',   [8 4 6]
        'drop O4 kick',      [8 4 2]
        'only O2 route',     4
    };

    fprintf('instance %s   budget %d iterations   seeds %s\n', ...
            instName, BUDGET, mat2str(SEEDS));
    fprintf('BKS: %d vehicles, %.2f\n\n', BKS_VEH, BKS_DIST);

    fprintf('%-16s %5s %5s %5s %10s %8s %8s\n', ...
            'configuration', 'ops', 'veh', 'hit20', 'dist', 'gap%', 'time');
    fprintf('%s\n', repmat('-', 1, 64));

    for c = 1:size(cfg, 1)
        name = cfg{c, 1};
        ops  = cfg{c, 2};
        vehs = []; dists = []; tt = 0;

        for sd = SEEDS
            opts = struct('budget', BUDGET, 'seed', sd, 'opSet', ops, ...
                          'decideEvery', 20, 'record', false, 'verbose', false);
            t0 = tic;
            [~, out] = solve_rlgbka(P, opts);
            tt = tt + toc(t0);
            vehs(end+1)  = out.nveh;  %#ok<AGROW>
            dists(end+1) = out.dist;  %#ok<AGROW>
        end

        order = sortrows([vehs(:), dists(:)], [1 2]);
        mVeh  = order(ceil(size(order,1)/2), 1);
        mDist = order(ceil(size(order,1)/2), 2);
        gap   = 100 * (mDist - BKS_DIST) / BKS_DIST;

        fprintf('%-16s %5d %5d %5d %10.2f %8.2f %8.0f\n', ...
                name, numel(ops), mVeh, sum(vehs <= BKS_VEH), mDist, gap, tt);
    end

    fprintf('\n=== how to read this ===\n');
    fprintf('  hit20  counts runs that reached %d vehicles across %d seeds.\n', ...
            BKS_VEH, numel(SEEDS));
    fprintf('  Compare dist only among rows with the same veh value.\n');
end
