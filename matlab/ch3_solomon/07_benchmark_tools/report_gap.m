function report_gap(instName, cost, routes, bks)
%REPORT_GAP  Print the gap of one result against the best-known solution.
%
%   report_gap('c1_2_1', 2750.4, 20, bks)
%
% Two numbers decide a VRPTW result, in this order:
%   1. the number of vehicles  -- fewer is better, it dominates
%   2. the total distance      -- smaller is better, only compared at equal
%                                 vehicle count
%
% This mirrors the convention used on the SINTEF tables, so gaps reported here
% are directly comparable with published results.

    key = matlab.lang.makeValidName(instName);
    if ~isfield(bks, key)
        fprintf('%-10s  no best-known entry\n', instName);
        return;
    end
    b = bks.(key);

    if routes > b.routes
        fprintf('%-10s  veh %3d vs best %3d  (+%d)   dist %10.2f  [NOT comparable]\n', ...
                instName, routes, b.routes, routes - b.routes, cost);
        return;
    end

    gap = 100 * (cost - b.dist) / b.dist;
    flag = '';
    if abs(gap) < 1e-6, flag = '  <-- matches best known'; end
    fprintf('%-10s  veh %3d / %3d   dist %10.2f  best %10.2f   gap %+6.2f%%%s\n', ...
            instName, routes, b.routes, cost, b.dist, gap, flag);
end
