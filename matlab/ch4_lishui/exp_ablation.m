function exp_ablation(seeds, budget, F, cap)
% EXP_ABLATION  Two ablations that Chapter 3 does not cover for the whole day model.
%
%   (a) the congestion context removed.  The three state dimensions that carry the
%       share of driving time in each regime are held at zero and every decision is
%       attributed to the same regime, so the bandit can no longer keep three separate
%       estimates.  If the context is doing work, this must hurt.
%
%   (b) the operator set reduced to one arm.  Three single arm runs show whether the
%       three operators are worth combining at all, which is the same question Chapter
%       3 answers on the benchmark instances.
%
%   Both are compared against the full model from exp1_main.csv.

if nargin < 1 || isempty(seeds), seeds = 1:5; end
if nargin < 2 || isempty(budget), budget = 20; end
if nargin < 3 || isempty(F), F = 6; end
if nargin < 4 || isempty(cap), cap = 1200; end

rows = {};

% ---- (a) no congestion context ----
fprintf('\n(a) congestion context removed\n');
for s = seeds
    C = case_load('cap', cap, 'windows', [12 17 19]);
    [~, o] = solve_day(C, F, 'CBLNS', budget, s, false);
    rows{end+1} = struct('variant', 'no context', 'arm', 0, 'seed', s, ...
        'obj', o.obj, 'trips', o.trips, 'distance', o.distance, 'iters', o.iters); %#ok<AGROW>
    fprintf('  seed %d  obj %7.1f  trips %2d  iters %4d\n', s, o.obj, o.trips, o.iters);
end

% ---- (b) one arm only ----
arms = {'sector', 'worst', 'random'};
for k = 1:3
    fprintf('\n(b) only %s\n', arms{k});
    for s = seeds
        C = case_load('cap', cap, 'windows', [12 17 19]);
        [~, o] = solve_day(C, F, 'CBLNS', budget, s, true, k);
        rows{end+1} = struct('variant', ['only ' arms{k}], 'arm', k, 'seed', s, ...
            'obj', o.obj, 'trips', o.trips, 'distance', o.distance, 'iters', o.iters); %#ok<AGROW>
        fprintf('  seed %d  obj %7.1f  trips %2d  iters %4d\n', s, o.obj, o.trips, o.iters);
    end
end

T = struct2table([rows{:}]);
writetable(T, 'exp2_ablation.csv');

base = NaN;
if isfile('exp1_main.csv')
    T1 = readtable('exp1_main.csv');
    base = mean(T1.obj(strcmp(T1.method, 'CBLNS')));
end

fid = fopen('exp2_ablation_summary.txt', 'w');
if ~isnan(base)
    fprintf(fid, 'full model: %.1f\n\n', base);
end
fprintf(fid, '%-14s %8s %9s %9s %8s\n', 'variant', 'obj', 'obj_sd', 'trips', 'vs full');
variants = {'no context', 'only sector', 'only worst', 'only random'};
fprintf('\n%-14s %8s %9s %9s %8s\n', 'variant', 'obj', 'obj_sd', 'trips', 'vs full');
for v = 1:numel(variants)
    sel = strcmp(T.variant, variants{v});
    mu = mean(T.obj(sel)); sd = std(T.obj(sel)); tr = mean(T.trips(sel));
    if isnan(base)
        fprintf(fid, '%-14s %8.1f %9.1f %9.2f %8s\n', variants{v}, mu, sd, tr, '-');
        fprintf(   '%-14s %8.1f %9.1f %9.2f %8s\n', variants{v}, mu, sd, tr, '-');
    else
        fprintf(fid, '%-14s %8.1f %9.1f %9.2f %+8.1f\n', variants{v}, mu, sd, tr, mu - base);
        fprintf(   '%-14s %8.1f %9.1f %9.2f %+8.1f\n', variants{v}, mu, sd, tr, mu - base);
    end
end
fclose(fid);
fprintf('\nwrote exp2_ablation.csv and exp2_ablation_summary.txt\n');
end
