function T = baselines_only(budget, seeds, cap)
% BASELINES_ONLY  Run the four baselines at a fixed capacity.
%
%   The proposed method is not run here; its own table (results_cblns.csv) already
%   holds the same seeds.  Keeping the two apart means a change to the bandit never
%   forces the baselines to be recomputed.
%
%   At a capacity of 600 the fleet cannot deliver the whole demand, so the metric
%   that matters is the served share, not the distance.

if nargin < 1, budget = 60; end
if nargin < 2, seeds = 1:5; end
if nargin < 3, cap = 600; end

methods = {'ALNS', 'VNS', 'Tabu', 'GA'};
rows = {};

for m = 1:numel(methods)
    for s = seeds
        C = case_load('cap', cap, 'windows', [12 17 19]);
        out = run_method(C, methods{m}, budget, s);
        sch = sched_trips(C, out.trips);
        d = 0;
        for k = 1:numel(out.trips), d = d + trip_dist(C, out.trips{k}); end
        nServ = 0;
        for k = 1:numel(out.trips)
            if ~any(sch.unsched == k), nServ = nServ + sum(C.demand(out.trips{k})); end
        end
        served = nServ / sum(C.demand);
        rows{end+1} = struct('method', methods{m}, 'seed', s, 'capacity', cap, ...
            'trips', numel(out.trips), 'distance', d, 'served', served, ...
            'scheduled', numel(out.trips) - numel(sch.unsched), ...
            'makespan', sch.makespan, 'iters', out.iters); %#ok<AGROW>
        fprintf('%-6s seed %d  trips %2d  dist %7.1f  sched %2d/%2d  served %.4f  makespan %.2f\n', ...
            methods{m}, s, numel(out.trips), d, numel(out.trips) - numel(sch.unsched), ...
            numel(out.trips), served, sch.makespan);
        drawnow
    end
end

T = struct2table([rows{:}]);
writetable(T, sprintf('results_base_%d.csv', cap));

fprintf('\n%-6s %6s %10s %8s\n', 'method', 'trips', 'distance', 'served');
for m = 1:numel(methods)
    sel = strcmp(T.method, methods{m});
    fprintf('%-6s %6.2f %10.1f %8.4f\n', methods{m}, ...
        mean(T.trips(sel)), mean(T.distance(sel)), mean(T.served(sel)));
end
end
