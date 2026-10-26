function diag_construction()
%DIAG_CONSTRUCTION  Can a simple insertion construction reach the best-known
%vehicle count at all?
%
% Before blaming the local search for not consolidating 21 routes into 20, it
% matters whether 20 is reachable by construction in the first place.  If some
% customer ordering already yields 20 routes, the search only has to improve
% distance, which is a completely different (and much easier) problem.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    inst = read_vrptw_instance(fullfile(benchmark_dir(), 'instances200', 'C1_2_1.TXT'));
    S = vrptw_model(inst);

    n = S.n;
    idx = (2:S.N)';

    % ---- candidate orderings
    [~, oDue]   = sort(S.due(2:end));      orders{1} = oDue(:)' + 1;  names{1} = 'earliest due';
    [~, oReady] = sort(S.ready(2:end));    orders{2} = oReady(:)' + 1; names{2} = 'earliest ready';
    [~, oFar]   = sort(S.D(1, 2:end), 'descend');
    orders{3} = oFar(:)' + 1;              names{3} = 'farthest first';
    [~, oNear]  = sort(S.D(1, 2:end));
    orders{4} = oNear(:)' + 1;             names{4} = 'nearest first';
    ang = atan2(S.y(idx) - S.y(1), S.x(idx) - S.x(1));
    [~, oAng] = sort(ang);                 orders{5} = oAng(:)' + 1;   names{5} = 'polar angle';
    [~, oWin] = sort(S.due(2:end) - S.ready(2:end));
    orders{6} = oWin(:)' + 1;              names{6} = 'tightest window first';

    fprintf('=== construction variants on %s (BKS: 20 vehicles, 2704.57) ===\n\n', S.name);
    fprintf('%-24s %6s %10s %10s\n', 'ordering', 'veh', 'dist', 'feasible');
    fprintf('%s\n', repmat('-', 1, 54));
    bestVeh = inf;
    for c = 1:numel(orders)
        r = vrptw_construct(S, orders{c});
        R = vrptw_eval(S, r);
        fprintf('%-24s %6d %10.2f %10d\n', names{c}, R.nveh, R.cost, R.feasible);
        bestVeh = min(bestVeh, R.nveh);
    end

    % ---- random restarts on the best ordering
    fprintf('\n=== 50 random-order constructions ===\n');
    rng(0);
    veh = zeros(1, 50);
    for t = 1:50
        p = randperm(n);
        r = vrptw_construct(S, p + 1);
        R = vrptw_eval(S, r);
        veh(t) = R.nveh;
    end
    fprintf('  vehicle counts: min %d, median %d, max %d\n', ...
            min(veh), median(veh), max(veh));
    fprintf('  how many reached 20: %d / 50\n', sum(veh <= 20));

    fprintf('\n=== overall conclusion ===\n');
    if min([bestVeh, min(veh)]) <= 20
        fprintf('  20 routes IS reachable by construction; the local search is the bottleneck.\n');
    else
        fprintf('  20 routes is NOT reachable by construction on this instance.\n');
        fprintf('  Route consolidation needs an explicit route-elimination operator,\n');
        fprintf('  not a stronger local search.\n');
    end
end
