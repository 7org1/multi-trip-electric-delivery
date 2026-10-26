function smoke_v2(timeLimit)
%SMOKE_V2  Quick check that the three new schedulers run and produce sane output.
%
%   Not a result, only a smoke test: 40 seconds on one instance.  Its purpose is to
%   catch a syntax error or an obviously wrong operator distribution before the
%   overnight sweep spends five hours on the same code.

    if nargin < 1 || isempty(timeLimit), timeLimit = 40; end

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    addpath(fullfile(here, '..', '09_solvers'));

    inst = read_vrptw_instance(fullfile(benchmark_dir(), 'instances200', 'R1_2_1.TXT'));
    S = vrptw_model(inst);
    P = problem_static(S);

    adapt = @(id, Pp, r, ctx) rlgbka_ops2(id, Pp, r, ...
                struct('lam', ctx.lam, 'scale', ctx.scale));

    names = {'pure', 'thompson', 'linucb-sched'};
    modes = {'pure', 'thompson', 'linucb'};
    extras = {struct('pureArm', 2), struct(), struct('alphaMode', 'sched')};

    fprintf('%-14s %12s %8s %7s %9s %s\n', ...
            'scheduler', 'result', 'iters', 'wins', 'served', 'opUse');
    fprintf('%s\n', repmat('-', 1, 76));

    for k = 1:numel(modes)
        o = struct('timeLimit', timeLimit, 'seed', 1, 'verbose', false, ...
                   'opSet', [3 5 2], 'opFun', adapt, 'mode', modes{k});
        f = fieldnames(extras{k});
        for j = 1:numel(f)
            o.(f{j}) = extras{k}.(f{j});
        end

        [best, out] = solve_rlgbka_v2(P, o);

        served = 0;
        for q = 1:numel(best), served = served + numel(best{q}); end
        uniq = [];
        for q = 1:numel(best), uniq = [uniq, best{q}(:).']; end %#ok<AGROW>

        fprintf('%-14s %5d/%8.2f %8d %7d %6d/%d %s\n', ...
                names{k}, out.nveh, out.dist, out.iter, sum(out.opSucc), ...
                numel(unique(uniq)), P.n, mat2str(out.opUse));
    end
end
