function smoke_variants(timeLimit)
%SMOKE_VARIANTS  Check that the three balance variants run and behave differently.
%
%   The three variants all attack the same defect: the exploration bonus is 50-130
%   times larger than the value term, so the argmax reduces to "pick the least
%   sampled arm", i.e. uniform rotation.  Each fixes it a different way and they
%   should therefore leave visibly different operator-usage distributions:
%
%       V1  reward x50       balance shifted, so exploitation finally matters
%       V2  alpha / sqrt(n)  exploration dies out instead of persisting
%       V3  standardise      both terms put on a common scale
%
%   If all four rows below show a near-uniform opUse, the variants changed nothing
%   and the five-hour sweep would be wasted.

    if nargin < 1 || isempty(timeLimit), timeLimit = 70; end

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    addpath(fullfile(here, '..', '09_solvers'));

    inst = read_vrptw_instance(fullfile(benchmark_dir(), 'instances200', 'R1_2_1.TXT'));
    S = vrptw_model(inst);
    P = problem_static(S);
    adapt = @(id, Pp, r, ctx) rlgbka_ops2(id, Pp, r, ...
                struct('lam', ctx.lam, 'scale', ctx.scale));

    names  = {'reference (sched)', 'V1 reward x50', 'V2 alpha/sqrt(n)', 'V3 standardise'};
    extras = {struct(), ...
              struct('rewardScale', 50), ...
              struct('alphaDecay', 'fast'), ...
              struct('standardize', true, 'alpha', 0.5)};

    fprintf('%-20s %12s %8s %s\n', 'variant', 'result', 'iters', 'opUse');
    fprintf('%s\n', repmat('-', 1, 72));

    for k = 1:numel(names)
        o = struct('timeLimit', timeLimit, 'seed', 1, 'verbose', false, ...
                   'opSet', [3 5 2], 'opFun', adapt, 'mode', 'linucb', ...
                   'alphaMode', 'sched');
        f = fieldnames(extras{k});
        for j = 1:numel(f), o.(f{j}) = extras{k}.(f{j}); end

        [best, out] = solve_rlgbka_v2(P, o);
        served = 0;
        for q = 1:numel(best), served = served + numel(best{q}); end
        fprintf('%-20s %5d/%7.1f %8d %s  (served %d/%d)\n', ...
                names{k}, out.nveh, out.dist, out.iter, mat2str(out.opUse), served, P.n);
    end
end
