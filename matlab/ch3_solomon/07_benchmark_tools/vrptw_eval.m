function R = vrptw_eval(S, routes)
%VRPTW_EVAL  Evaluate a complete solution (a set of routes).
%
%   R = vrptw_eval(S, routes)
%
%   routes  cell array; each cell is a vector of customer indices 2..N
%
%   R.cost      total distance  (the VRPTW objective, after the vehicle count)
%   R.nveh      number of non-empty routes
%   R.feasible  true when every route satisfies capacity and time windows
%   R.nBad      number of infeasible routes
%   R.loads     [nveh x 1] load of each route
%
% THE OBJECTIVE IS LEXICOGRAPHIC
%   Benchmark VRPTW compares solutions by (number of vehicles, then distance).
%   Reporting a distance without its vehicle count is meaningless, so both are
%   always returned and `report_gap` refuses to compare across different
%   vehicle counts.

    nR = numel(routes);
    R.cost     = 0;
    R.nveh     = 0;
    R.feasible = true;
    R.nBad     = 0;
    R.loads    = zeros(nR, 1);

    for k = 1:nR
        rt = routes{k};
        if isempty(rt)
            continue;
        end
        [ok, dist, ~, load] = vrptw_route_eval(S, rt);
        R.cost     = R.cost + dist;
        R.nveh     = R.nveh + 1;
        R.loads(k) = load;
        if ~ok
            R.feasible = false;
            R.nBad     = R.nBad + 1;
        end
    end

    if R.nveh > S.m
        R.feasible = false;
    end
end
