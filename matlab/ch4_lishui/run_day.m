function T = run_day(budget, seeds, F, cap)
% RUN_DAY  Compare the five operator policies on the whole-day model.
%
%   Every method solves the same instance with the same fleet, the same
%   construction, repair, acceptance rule and budget.  Only the rule that picks the
%   destroy operator differs, so the comparison isolates the policy.
%
%   Results go to results_day_<cap>_F<F>.csv and a plain text digest.

if nargin < 1, budget = 20; end
if nargin < 2, seeds = 1:5; end
if nargin < 3, F = 5; end
if nargin < 4, cap = 2400; end

methods = {'CBLNS', 'ALNS', 'VNS', 'Tabu', 'GA'};
rows = {};

for m = 1:numel(methods)
    for s = seeds
        C = case_load('cap', cap, 'windows', [12 17 19]);
        t0 = tic;
        [~, o] = solve_day(C, F, methods{m}, budget, s);
        el = toc(t0);
        if isempty(o) || ~o.feasible
            rows{end+1} = struct('method', methods{m}, 'seed', s, ...
                'trips', NaN, 'distance', NaN, 'obj', NaN, 'feasible', 0, ...
                'iters', 0, 'seconds', el); %#ok<AGROW>
            fprintf('%-6s seed %d  INFEASIBLE  %.0fs\n', methods{m}, s, el);
            continue
        end
        sh = sum(o.share, 1) / max(1, sum(o.share(:)));
        rows{end+1} = struct('method', methods{m}, 'seed', s, ...
            'trips', o.trips, 'distance', o.distance, 'obj', o.obj, ...
            'feasible', 1, 'iters', o.iters, ...
            'secSector', sh(1), 'secWorst', sh(2), 'secRandom', sh(3), ...
            'seconds', el); %#ok<AGROW>
        fprintf('%-6s seed %d  obj %7.1f  trips %2d  dist %7.1f  iters %5d  arms [%.2f %.2f %.2f]  %.0fs\n', ...
            methods{m}, s, o.obj, o.trips, o.distance, o.iters, sh(1), sh(2), sh(3), el);
        drawnow limitrate
    end
end

T = struct2table([rows{:}]);
writetable(T, sprintf('results_day_%d_F%d.csv', cap, F));

fprintf('\n%-7s %7s %9s %9s %8s\n', 'method', 'trips', 'distance', 'objective', 'feasible');
for m = 1:numel(methods)
    sel = strcmp(T.method, methods{m});
    if ~any(sel), continue, end
    fprintf('%-7s %7.2f %9.1f %9.1f %8.1f\n', methods{m}, ...
        mean(T.trips(sel), 'omitnan'), mean(T.distance(sel), 'omitnan'), ...
        mean(T.obj(sel), 'omitnan'), mean(T.feasible(sel)));
end

fid = fopen(sprintf('SUMMARY_day_%d_F%d.txt', cap, F), 'w');
fprintf(fid, 'whole-day solve, fleet %d, capacity %d, budget %g s\n\n', F, cap, budget);
fprintf(fid, '%-7s %7s %9s %9s %8s\n', 'method', 'trips', 'distance', 'objective', 'feasible');
for m = 1:numel(methods)
    sel = strcmp(T.method, methods{m});
    if ~any(sel), continue, end
    fprintf(fid, '%-7s %7.2f %9.1f %9.1f %8.1f\n', methods{m}, ...
        mean(T.trips(sel), 'omitnan'), mean(T.distance(sel), 'omitnan'), ...
        mean(T.obj(sel), 'omitnan'), mean(T.feasible(sel)));
end
fclose(fid);
fprintf('\nwrote results_day_%d_F%d.csv and its digest\n', cap, F);
end
