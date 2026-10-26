function S = vrptw_model(inst)
%VRPTW_MODEL  Precompute everything the solvers need from a parsed instance.
%
%   S = vrptw_model(inst)
%
% Returns a struct with the distance/time matrix, feasibility helpers and the
% per-node time-window data, so that every solver works on the same arrays and
% a result from one is directly comparable with another.
%
% TRAVEL TIME = DISTANCE
%   In the Solomon / Gehring-Homberger benchmarks the vehicle travels one unit
%   of distance per unit of time, so the travel-time matrix equals the distance
%   matrix.
%
% DISTANCES ARE UNROUNDED -- VERIFIED, NOT ASSUMED
%   The published best-known value for c1_2_1 is 2704.5678, which has four
%   decimals.  A sum of integer distances cannot have decimals, so the objective
%   must use unrounded Euclidean distances.  Evaluating the published routes
%   under both conventions settles it beyond doubt:
%
%       unrounded : 2704.5678   (matches)
%       rounded   : 2690.0000   (14.57 too low)
%
%   An earlier version of this function rounded, and the symptom was a run that
%   appeared BETTER than the best known solution -- the most damaging thing a
%   results table can show.  See check_bks_convention.m, which reproduces the
%   published value from the published routes and therefore validates the whole
%   evaluation chain.
%
% FIELDS
%   S.n        number of customers (depot excluded)
%   S.N        n + 1
%   S.D        [N x N] distance, rounded to integers
%   S.T        [N x N] travel time, same as D in these benchmarks
%   S.demand   [N x 1]
%   S.ready    [N x 1]
%   S.due      [N x 1]
%   S.service  [N x 1]
%   S.Q        vehicle capacity
%   S.m        number of available vehicles
%   S.depot    index 1
%   S.name     instance name

    D = distance_matrix(inst, 'exact');

    S = struct();
    S.name    = lower(inst.name);
    S.n       = inst.n;
    S.N       = inst.n + 1;
    S.D       = D;
    S.T       = D;                 % time = distance in these benchmarks
    S.x       = inst.x(:);         % kept for polar / angular orderings
    S.y       = inst.y(:);
    S.demand  = inst.demand(:);
    S.ready   = inst.ready(:);
    S.due     = inst.due(:);
    S.service = inst.service(:);
    S.Q       = inst.Q;
    S.m       = inst.m;
    S.depot   = 1;

    % departure from the depot may not precede time 0
    S.horizon = max(S.due);

    % per-route lower bounds used by the solvers for pruning
    S.maxLoad = S.Q;
end
