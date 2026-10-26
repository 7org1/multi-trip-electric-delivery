function T = run_base_rerun(budget, seeds, F, cap)
% RUN_BASE_RERUN  Re-run the four baselines with the current code.
%
%   The baselines in results_day_1200_F6.csv were measured before the congestion mix
%   was cached, when every iteration did less work and the iteration count was higher.
%   This driver re-measures them with exactly the code that produced the proposed
%   method's numbers, so that the comparison is between versions of the same program.

if nargin < 1, budget = 20; end
if nargin < 2, seeds = 1:5; end
if nargin < 3, F = 6; end
if nargin < 4, cap = 1200; end

methods = {'ALNS', 'VNS', 'Tabu', 'GA'};
rows = {};

for m = 1:numel(methods)
    for s = seeds
        C = case_load('cap', cap, 'windows', [12 17 19]);
        t0 = tic;
        [~, o] = solve_day(C, F, methods{m}, budget, s);
        el = toc(t0);
        if isempty(o) || ~o.feasible
            fprintf('%-6s seed %d  INFEASIBLE  %.0fs\n', methods{m}, s, el);
            continue
        end
        rows{end+1} = struct('method', methods{m}, 'seed', s, ...
            'trips', o.trips, 'distance', o.distance, 'obj', o.obj, ...
            'iters', o.iters, 'seconds', el); %#ok<AGROW>
        fprintf('%-6s seed %d  obj %7.1f  trips %2d  dist %7.1f  iters %4d  %.0fs\n', ...
            methods{m}, s, o.obj, o.trips, o.distance, o.iters, el);
        drawnow limitrate
    end
end

T = struct2table([rows{:}]);
writetable(T, 'results_base_rerun.csv');

fid = fopen('SUMMARY_base_rerun.txt', 'w');
fprintf(fid, 'four baselines, current code, fleet %d, capacity %d, budget %g s\n\n', F, cap, budget);
fprintf(fid, '%-7s %7s %10s %10s %9s %9s %8s %8s\n', ...
    'method', 'trips', 'dist', 'dist_sd', 'obj', 'obj_sd', 'best', 'worst');
for m = 1:numel(methods)
    sel = strcmp(T.method, methods{m});
    if ~any(sel), continue, end
    fprintf(fid, '%-7s %7.2f %10.1f %10.1f %9.1f %9.1f %8.1f %8.1f\n', methods{m}, ...
        mean(T.trips(sel)), mean(T.distance(sel)), std(T.distance(sel)), ...
        mean(T.obj(sel)), std(T.obj(sel)), min(T.obj(sel)), max(T.obj(sel)));
end
fclose(fid);

fprintf('\n%-7s %7s %10s %10s %9s\n', 'method', 'trips', 'dist', 'dist_sd', 'obj');
for m = 1:numel(methods)
    sel = strcmp(T.method, methods{m});
    if ~any(sel), continue, end
    fprintf('%-7s %7.2f %10.1f %10.1f %9.1f\n', methods{m}, ...
        mean(T.trips(sel)), mean(T.distance(sel)), std(T.distance(sel)), mean(T.obj(sel)));
end
fprintf('\nwrote results_base_rerun.csv and SUMMARY_base_rerun.txt\n');
end
