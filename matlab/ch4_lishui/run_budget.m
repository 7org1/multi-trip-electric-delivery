function T = run_budget(budgets, seeds, F, cap)
% RUN_BUDGET  Objective against the CPU budget, for every method.
%
%   Feeds the anytime curve: for each budget and each method the mean objective over
%   the seeds is recorded, so that the choice of twenty seconds can be justified by
%   data instead of by assertion.

if nargin < 1 || isempty(budgets), budgets = [5 10 20 40]; end
if nargin < 2 || isempty(seeds), seeds = 1:3; end
if nargin < 3 || isempty(F), F = 6; end
if nargin < 4 || isempty(cap), cap = 1200; end

methods = {'CBLNS', 'ALNS', 'VNS', 'Tabu', 'GA'};
rows = {};

for b = budgets
    for m = 1:numel(methods)
        for s = seeds
            C = case_load('cap', cap, 'windows', [12 17 19]);
            t0 = tic;
            [~, o] = solve_day(C, F, methods{m}, b, s);
            el = toc(t0);
            if isempty(o) || ~o.feasible, continue, end
            rows{end+1} = struct('method', methods{m}, 'budget', b, 'seed', s, ...
                'obj', o.obj, 'trips', o.trips, 'distance', o.distance, ...
                'iters', o.iters, 'seconds', el); %#ok<AGROW>
            fprintf('%-6s budget %2d seed %d  obj %7.1f  trips %2d  iters %4d  %.0fs\n', ...
                methods{m}, b, s, o.obj, o.trips, o.iters, el);
            drawnow limitrate
        end
    end
end

T = struct2table([rows{:}]);
writetable(T, 'results_budget.csv');

fid = fopen('SUMMARY_budget.txt', 'w');
fprintf(fid, 'objective against the CPU budget, fleet %d, capacity %d\n\n', F, cap);
fprintf(fid, '%-7s', 'budget');
for m = 1:numel(methods), fprintf(fid, '%12s', methods{m}); end
fprintf(fid, '\n');
for b = budgets
    fprintf(fid, '%-7d', b);
    for m = 1:numel(methods)
        sel = T.budget == b & strcmp(T.method, methods{m});
        if any(sel), fprintf(fid, '%12.1f', mean(T.obj(sel))); else, fprintf(fid, '%12s', '-'); end
    end
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('\nwrote results_budget.csv and SUMMARY_budget.txt\n');
end
