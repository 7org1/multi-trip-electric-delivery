function T = cblns_only(budget, seeds, cap)
% CBLNS_ONLY  Run the proposed method alone, with and without the fourth operator.
%
%   The four baselines are frozen in results_matlab.csv and are not re-run here.
%   This driver only answers two questions:
%
%     1. does the whole-trip neighbourhood reduce the trip count
%     2. which operators does the bandit actually choose
%
%   The second answer is what the coupling argument of Chapter 4 rests on, so the
%   share of each arm is recorded per run.

if nargin < 1, budget = 60; end
if nargin < 2, seeds = 1:5; end
if nargin < 3, cap = 600; end

sets = {'ch3', 'full'};
rows = {};

for a = 1:2
    for s = seeds
        C = case_load('cap', cap, 'windows', [12 17 19]);
        out = cblns_v3(C, budget, s, 'decay', sets{a});
        sch = sched_trips(C, out.trips);
        d = 0;
        for k = 1:numel(out.trips), d = d + trip_dist(C, out.trips{k}); end
        nServ = 0;
        for k = 1:numel(out.trips)
            if ~any(sch.unsched == k), nServ = nServ + sum(C.demand(out.trips{k})); end
        end
        rows{end+1} = struct('arms', sets{a}, 'seed', s, 'trips', numel(out.trips), ...
            'distance', d, 'served', nServ / sum(C.demand), ...
            'makespan', sch.makespan, 'iters', out.iters, ...
            'share', out.share); %#ok<AGROW>
        fprintf('%-4s seed %d  trips %2d  dist %7.1f  served %.3f  iters %5d  arms %s\n', ...
            sets{a}, s, numel(out.trips), d, nServ / sum(C.demand), out.iters, ...
            mat2str(round(out.share, 2)));
        drawnow
    end
end

T = struct2table([rows{:}]);
writetable(T, 'results_cblns.csv');

fprintf('\n%-6s %6s %10s %8s\n', 'arms', 'trips', 'distance', 'served');
for a = 1:2
    sel = strcmp(T.arms, sets{a});
    fprintf('%-6s %6.2f %10.1f %8.3f\n', sets{a}, ...
        mean(T.trips(sel)), mean(T.distance(sel)), mean(T.served(sel)));
end
end
