function check_bks_convention()
%CHECK_BKS_CONVENTION  Settle the distance convention by evaluating the actual
%best-known solution of c1_2_1.
%
%   The published value is 2704.5678, which has four decimals.  A sum of
%   INTEGER Euclidean distances cannot have decimals, so the benchmark objective
%   must use unrounded distances.  This script proves it rather than assumes it:
%   it evaluates the same published routes under both conventions and compares
%   with the published value.
%
%   Getting this wrong is not cosmetic.  With rounded distances the reported gap
%   is off by enough to make a run appear BETTER than the best known solution,
%   which is the single most damaging thing a results table can show.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(benchmark_dir());

    inst = read_vrptw_instance(fullfile(benchmark_dir(), 'instances200', 'C1_2_1.TXT'));
    routes = read_bks_routes(fullfile(benchmark_dir(), 'bks_solutions', 'c1_2_1.txt'));

    PUBLISHED = 2704.5678;

    % ---- unrounded
    Du = distance_matrix(inst, 'exact');
    du = totalDist(Du, routes, inst.n);

    % ---- rounded
    Dr = distance_matrix(inst, 'round');
    dr = totalDist(Dr, routes, inst.n);

    % ---- feasibility of the published routes under my checker
    % The published routes number customers 1..n with 0 as the depot; the model
    % indexes the depot as 1 and customers as 2..N.  Forgetting the shift makes
    % every route look infeasible and inflates the distance by a wide margin,
    % which is exactly what happened on the first run of this check.
    S = vrptw_model(inst);
    shifted = cellfun(@(r) r + 1, routes, 'UniformOutput', false);
    R = vrptw_eval(S, shifted);

    fprintf('published best known   : %.4f  (%d routes)\n', PUBLISHED, numel(routes));
    fprintf('unrounded euclidean    : %.4f   diff %+.4f\n', du, du - PUBLISHED);
    fprintf('rounded   euclidean    : %.4f   diff %+.4f\n', dr, dr - PUBLISHED);
    fprintf('\n');
    fprintf('feasible under my checker : %d  (%d bad routes)\n', ...
            R.feasible, R.nBad);
    fprintf('route count               : %d\n', R.nveh);
    fprintf('distance from my model    : %.4f\n', R.cost);

    fprintf('\n=== verdict ===\n');
    if abs(du - PUBLISHED) < 0.01
        fprintf('USE UNROUNDED EUCLIDEAN.  It reproduces the published value.\n');
    elseif abs(dr - PUBLISHED) < 0.01
        fprintf('USE ROUNDED EUCLIDEAN.  It reproduces the published value.\n');
    else
        fprintf('NEITHER matches -- check the instance coordinates or the route order.\n');
    end
end

function routes = read_bks_routes(f)
    lines = regexp(fileread(f), '\r\n|\r|\n', 'split');
    routes = {};
    for k = 1:numel(lines)
        s = strtrim(lines{k});
        if strncmpi(s, 'route', 5)
            v = sscanf(s(6:end), '%f');
            routes{end+1} = v(:)'; %#ok<AGROW>
        end
    end
end

function d = totalDist(D, routes, n)
    d = 0;
    for r = 1:numel(routes)
        rt = routes{r};
        prev = 1;
        for k = 1:numel(rt)
            d = d + D(prev, rt(k) + 1);   % +1: customer 0 is the depot
            prev = rt(k) + 1;
        end
        d = d + D(prev, 1);
    end
end
