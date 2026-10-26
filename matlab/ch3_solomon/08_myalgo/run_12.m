function run_12(mode, part, opts_json)
%RUN_12  Twelve-instance sweep for one scheduling mode, one part at a time.
%
%   run_12('roundrobin', 1)        % part 1 of 3
%   run_12('roundrobin', [1 2 3])  % all parts in one process
%
%   The twelve instances are two per class, so every class is represented and the
%   fleet-minimisation and distance behaviour can be read separately.
%
%   Each run is 300 CPU seconds; five seeds per instance.  Results are appended to
%   build/08_myalgo/results12/<mode>_part<k>.csv so a killed part loses only its
%   own work.
%
%   THIS RUNS THE NEW THREE-OPERATOR SET
%       sector removal, random removal, worst removal, via rlgbka_ops2
%   with the scheduling mode given.  The previous twelve-instance baseline was
%   produced with the old four-operator set, so the two are not comparable and the
%   old numbers cannot be reused for chapter 3.

    if nargin < 1 || isempty(mode), mode = 'roundrobin'; end
    if nargin < 2 || isempty(part), part = 1; end
    if nargin < 3, opts_json = ''; end

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    addpath(fullfile(here, '..', '09_solvers'));

    INST = {'c1_2_1','c1_2_4', 'c2_2_1','c2_2_4', ...
            'r1_2_1','r1_2_4', 'r2_2_1','r2_2_4', ...
            'rc1_2_1','rc1_2_4', 'rc2_2_1','rc2_2_4'};

    N_PART = 3;
    groups = {1:4, 5:8, 9:12};         % four instances per part
    mine = [];
    for p = part(:).'
        mine = [mine, groups{p}]; %#ok<AGROW>
    end

    SEEDS = 1:5;
    TL = 300;

    bks = load_bks();
    bdir = benchmark_dir();

    outdir = fullfile(here, 'results12');
    if ~exist(outdir, 'dir'), mkdir(outdir); end
    tag = sprintf('%s_part%s', mode, strrep(mat2str(part(:).'), ' ', ''));

    adapt = @(id, Pp, r, ctx) rlgbka_ops2(id, Pp, r, ...
                struct('lam', ctx.lam, 'scale', ctx.scale));

    solverMode = mode;
    if strcmp(mode, 'linucb-sched'), solverMode = 'linucb'; end
    base = struct('timeLimit', TL, 'verbose', false, ...
                  'opSet', [3 5 2], 'opFun', adapt, 'mode', solverMode);
    if strcmp(mode, 'linucb-sched'), base.alphaMode = 'sched'; end
    if strcmp(mode, 'pure'), base.pureArm = 2; end     % arm 2 is random removal
    if ~isempty(opts_json)
        extra = jsondecode(opts_json);
        fn = fieldnames(extra);
        for k = 1:numel(fn), base.(fn{k}) = extra.(fn{k}); end
    end

    fprintf('=== mode %s, part %s, instances %s ===\n', mode, mat2str(part), ...
            strjoin(INST(mine), ' '));

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
            o = base;
            o.seed = sd;
            t0 = cputime;
            % Two solver files, on purpose.  The A/B/C sweep was already running when
            % the pure / thompson / scheduled-alpha schedulers were added, so those
            % went into solve_rlgbka_v2, which is a line-by-line copy of the original
            % plus the new modes.  Dispatching here keeps each result attributable to
            % one version of the code; the two files were diffed to confirm the only
            % differences are the added modes.
            if any(strcmp(mode, {'pure', 'thompson', 'linucb-sched'}))
                [best, out] = solve_rlgbka_v2(P, o);
            else
                [best, out] = solve_rlgbka_online(P, o);
            end
            wall = cputime - t0;

            served = 0;
            for k = 1:numel(best), served = served + numel(best{k}); end
            complete = (served == P.n);

            gap = 100 * (out.dist - b.dist) / b.dist;
            fid = fopen(fullfile(outdir, [tag '.csv']), 'a');
            fprintf(fid, '%s,%s,%d,%d,%.4f,%.4f,%d,%d,%d,%.1f\n', ...
                    name, mode, sd, out.nveh, out.dist, gap, ...
                    double(out.feasible && complete), out.iter, ...
                    sum(out.opSucc), wall);
            fclose(fid);

            fprintf('  %-9s seed %d: %2d / %9.2f  gap %6.2f%%  iters %6d  wins %4d  %.0fs\n', ...
                    name, sd, out.nveh, out.dist, gap, out.iter, sum(out.opSucc), wall);
        end
    end
    fprintf('=== wrote %s ===\n', fullfile(outdir, [tag '.csv']));
end
