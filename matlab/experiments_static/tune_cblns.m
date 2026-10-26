function T = tune_cblns(budget, seeds, cap)
% TUNE_CBLNS  Grid over the cooling rule and the two guards, at a fixed capacity.
%
%   The aim is stability, not the best single seed.  A configuration is adopted
%   only if every seed lands near the group mean, because a method that blows up on
%   one seed in five cannot be compared with anything.
%
%   cooling  'dyn'  the horizon re-estimated from the observed iteration rate
%            'fix'  the horizon fixed at budget*40
%   guards   the 5% exploration floor and the drift guard, on or off

if nargin < 1, budget = 60; end
if nargin < 2, seeds = 1:5; end
if nargin < 3, cap = 800; end

cfgs = { 'dyn', true;  'dyn', false;  'fix', false;  'fix', true };
rows = {};

for i = 1:size(cfgs, 1)
    for s = seeds
        C = case_load('cap', cap, 'windows', [12 17 19]);
        out = cblns_v3(C, budget, s, 'decay', 'ch3', cfgs{i, 1}, cfgs{i, 2});
        d = 0;
        for k = 1:numel(out.trips), d = d + trip_dist(C, out.trips{k}); end
        rows{end+1} = struct('cooling', cfgs{i, 1}, 'guards', cfgs{i, 2}, ...
            'seed', s, 'trips', numel(out.trips), 'distance', d, ...
            'iters', out.iters); %#ok<AGROW>
        fprintf('%-3s guards %d  seed %d  trips %2d  dist %7.1f  iters %5d\n', ...
            cfgs{i, 1}, cfgs{i, 2}, s, numel(out.trips), d, out.iters);
        drawnow
    end
end

T = struct2table([rows{:}]);
writetable(T, 'results_tune.csv');

fprintf('\n%-4s %7s %6s %10s %8s %8s\n', 'cool', 'guards', 'trips', 'dist', 'sd', 'worst');
for i = 1:size(cfgs, 1)
    sel = strcmp(T.cooling, cfgs{i, 1}) & (T.guards == cfgs{i, 2});
    d = T.distance(sel);
    fprintf('%-4s %7d %6.2f %10.1f %8.1f %8.1f\n', cfgs{i, 1}, cfgs{i, 2}, ...
        mean(T.trips(sel)), mean(d), std(d), max(d));
end
end
