function run_variant(part)
%RUN_VARIANT  Twelve instances x five seeds for each of the three balance variants.
%
%   WHY THESE THREE, IN ONE PLACE
%   All three attack the same measured defect: the exploration bonus is 50-130 times
%   larger than the value term, so LinUCB-sched reduces to picking the least sampled
%   arm and therefore to uniform rotation.  Each removes that domination differently:
%
%       V1  rewardScale 50      the value term is scaled up, so exploitation matters
%       V2  alphaDecay fast     exploration decays as 1/n instead of sqrt(ln t / n)
%       V3  standardise         both terms are put on a common scale, alpha = 0.5
%
%   They are expected to land in different places.  A short pilot gave operator
%   shares of 5/65/29, 0.6/91/8 and 36/29/35 per cent respectively, so V2 collapses
%   onto one arm and V3 becomes near-uniform; that is the prediction this sweep
%   tests at twelve instances.
%
%   part splits the twelve instances into three groups, so three processes cover the
%   whole design in the same wall time as one.

    if nargin < 1 || isempty(part), part = 1; end

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    addpath(fullfile(here, '..', '09_solvers'));

    INST = {'c1_2_1','c1_2_4', 'c2_2_1','c2_2_4', ...
            'r1_2_1','r1_2_4', 'r2_2_1','r2_2_4', ...
            'rc1_2_1','rc1_2_4', 'rc2_2_1','rc2_2_4'};
    groups = {1:4, 5:8, 9:12};
    mine = groups{part};

    SEEDS = 1:5;
    TL = 300;
    bks = load_bks();
    bdir = benchmark_dir();

    outdir = fullfile(here, 'results12');
    if ~exist(outdir, 'dir'), mkdir(outdir); end

    variants = { ...
        'linucb_v1_reward50', struct('rewardScale', 50); ...
        'linucb_v2_fastdecay', struct('alphaDecay', 'fast'); ...
        'linucb_v3_standard',  struct('standardize', true, 'alpha', 0.5)};

    adapt = @(id, Pp, r, ctx) rlgbka_ops2(id, Pp, r, ...
                struct('lam', ctx.lam, 'scale', ctx.scale));

    for v = 1:size(variants, 1)
        tag = sprintf('%s_part%d', variants{v, 1}, part);
        fprintf('=== %s : instances %s ===\n', variants{v, 1}, strjoin(INST(mine), ' '));

        fid = fopen(fullfile(outdir, [tag '.csv']), 'w');
        fprintf(fid, 'instance,mode,seed,veh,dist,gap,feasible,iters,wins,wall\n');
        fclose(fid);

        for i = mine
            name = INST{i};
            inst = read_vrptw_instance(fullfile(bdir, 'instances200', [upper(name) '.TXT']));
            S = vrptw_model(inst);
            P = problem_static(S);
            b = bks.(lower(name));

            for sd = SEEDS
                o = struct('timeLimit', TL, 'seed', sd, 'verbose', false, ...
                           'opSet', [3 5 2], 'opFun', adapt, ...
                           'mode', 'linucb', 'alphaMode', 'sched');
                f = fieldnames(variants{v, 2});
                for j = 1:numel(f), o.(f{j}) = variants{v, 2}.(f{j}); end

                t0 = cputime;
                [best, out] = solve_rlgbka_v2(P, o);
                wall = cputime - t0;

                served = 0;
                for k = 1:numel(best), served = served + numel(best{k}); end
                complete = (served == P.n);
                gap = 100 * (out.dist - b.dist) / b.dist;

                fid = fopen(fullfile(outdir, [tag '.csv']), 'a');
                fprintf(fid, '%s,%s,%d,%d,%.4f,%.4f,%d,%d,%d,%.1f\n', ...
                        name, variants{v,1}, sd, out.nveh, out.dist, gap, ...
                        double(out.feasible && complete), out.iter, ...
                        sum(out.opSucc), wall);
                fclose(fid);

                fprintf('  %-9s seed %d: %2d / %9.2f  gap %6.2f%%  iters %6d  %.0fs\n', ...
                        name, sd, out.nveh, out.dist, gap, out.iter, wall);
            end
        end
    end
    fprintf('=== part %d done ===\n', part);
end
