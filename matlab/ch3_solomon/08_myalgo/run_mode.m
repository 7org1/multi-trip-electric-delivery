function run_mode(mode, instName, bksDist)
%RUN_MODE  Three seeds of one comparison configuration on the hardest instance.
%
%   run_mode('learned') | run_mode('roundrobin') | run_mode('handrule')
%
%   All three run for the same 300 CPU seconds per seed, on the same instance,
%   with the same four operators.  The only difference is how the operator is
%   chosen, so the comparison isolates the value of the choice.
%
%   R1_2_1 is used because it is the instance where the algorithm is furthest from
%   the best known solution: 22 vehicles against 20, and every baseline except
%   ALNS stalls at the constructive solution.  A gain that does not show up there
%   will not show up anywhere.

    if nargin < 1, mode = 'learned'; end
    if nargin < 2 || isempty(instName), instName = 'R1_2_1'; end
    if nargin < 3 || isempty(bksDist), bksDist = 4784.11; end

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    addpath(fullfile(here, '..', '09_solvers'));

    bdir = benchmark_dir();
    inst = read_vrptw_instance(fullfile(bdir, 'instances200', [instName '.TXT']));
    S = vrptw_model(inst);
    P = problem_static(S);

    BKS = bksDist;
    SEEDS = 1:3;
    OPTS = struct('timeLimit', 300, 'verbose', false, 'opSet', [4 6 8 9], 'mode', mode);

    res = zeros(numel(SEEDS), 7);
    fprintf('=== %s on %s ===\n', mode, instName);

    for i = 1:numel(SEEDS)
        o = OPTS;
        o.seed = SEEDS(i);
        t0 = cputime;
        [~, out] = solve_rlgbka_online(P, o);
        wall = cputime - t0;
        gap = 100 * (out.dist - BKS) / BKS;
        % opUse is indexed by action slot; with opSet [4 6 8 9] slot 1 is route
        % elimination
        res(i, :) = [out.nveh, out.dist, gap, out.iter, sum(out.opSucc), ...
                     out.opUse(1), wall];
        fprintf('  seed %d: %2d / %8.2f  gap %6.2f%%  iters %7d  wins %4d  op4 %5d  cpu %.0fs\n', ...
                SEEDS(i), out.nveh, out.dist, gap, out.iter, sum(out.opSucc), ...
                out.opUse(1), wall);
    end

    outdir = fullfile(here, 'results_coupling');
    if ~exist(outdir, 'dir'), mkdir(outdir); end
    T = table(SEEDS(:), res(:,1), res(:,2), res(:,3), res(:,4), res(:,5), res(:,6), res(:,7), ...
        'VariableNames', {'seed','veh','dist','gap','iters','wins','op4use','cpusecs'});
    writetable(T, fullfile(outdir, [instName '_' mode '.csv']));

    fprintf('  --- mean: veh %.2f  dist %.2f  gap %.2f%%  iters %.0f  wins %.0f  op4 %.0f\n\n', ...
            mean(res(:,1)), mean(res(:,2)), mean(res(:,3)), mean(res(:,4)), ...
            mean(res(:,5)), mean(res(:,6)));
end
