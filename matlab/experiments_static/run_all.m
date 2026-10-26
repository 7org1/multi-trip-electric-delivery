function T = run_all(budget, seeds, cap)
% RUN_ALL  Run every method on the case and return one row per run.
%
%   T = run_all()           60 s, seeds 1:3, capacity 800
%   T = run_all(60, 1:5, 800)
%
%   The instance, the budget and the seeds are the same for every method, so the
%   only difference is the search policy.

if nargin < 1, budget = 60; end
if nargin < 2, seeds = 1:3; end
if nargin < 3, cap = 800; end

methods = {'CBLNS', 'ALNS', 'VNS', 'Tabu', 'GA'};
rows = {};

for s = seeds
    for m = 1:numel(methods)
        C = case_load('cap', cap, 'windows', [12 17 19]);
        out = run_method(C, methods{m}, budget, s);
        sch = sched_trips(C, out.trips);
        [served, nServ, nTot] = served_share(C, out.trips, sch);

        dist = 0;
        for k = 1:numel(out.trips), dist = dist + trip_dist(C, out.trips{k}); end
        energy = 0; late = 0;
        for v = 1:C.FLEET
            soc = C.B;
            for k = 1:numel(sch.V(v).trips)
                trip = sch.V(v).trips{k};
                dep = sch.V(v).dep{k};
                [ok, arr, ~, socEnd] = trip_eval(C, trip, dep, soc);
                if ~ok, continue, end
                energy = energy + (soc - socEnd);

                if numel(arr) == numel(trip), late = late + sum(arr(:) > C.winE(trip(:)) + 1e-9); end
                soc = socEnd;
            end
        end
        charges = 0;
        for v = 1:C.FLEET, charges = charges + sch.V(v).charges; end

        rows{end+1} = struct('method', methods{m}, 'seed', s, 'capacity', cap, ...
            'trips', numel(out.trips), 'objective', out.obj, 'distance', dist, ...
            'scheduled', numel(out.trips) - numel(sch.unsched), ...
            'served', served, 'points_served', nServ, 'points_total', nTot, ...
            'makespan', sch.makespan, 'charges', charges, ...
            'energy', energy, 'late', late, 'iters', out.iters); %#ok<AGROW>

        fprintf('%-6s seed %d  trips %2d  dist %7.1f  served %.3f  makespan %.2f  iters %d\n', ...
            methods{m}, s, numel(out.trips), dist, served, sch.makespan, out.iters);
        drawnow
    end
end

% flatten and write
T = struct2table([rows{:}]);
writetable(T, 'results_matlab.csv');
fprintf('\nwrote results_matlab.csv\n\n');
fprintf('%-8s %6s %10s %8s %9s\n', 'method', 'trips', 'distance', 'served', 'makespan');
for m = 1:numel(methods)
    sel = strcmp(T.method, methods{m});
    if ~any(sel), continue, end
    fprintf('%-8s %6.2f %10.1f %8.3f %9.2f\n', methods{m}, ...
        mean(T.trips(sel)), mean(T.distance(sel)), ...
        mean(T.served(sel)), mean(T.makespan(sel)));
end
end


function [share, nServ, nTot] = served_share(C, trips, sch)
% fraction of the demand that the schedule actually delivers
nTot = sum(C.demand);
nServ = 0;
uns = sch.unsched;
for k = 1:numel(trips)
    if any(uns == k), continue, end
    nServ = nServ + sum(C.demand(trips{k}));
end
share = nServ / nTot;
end
