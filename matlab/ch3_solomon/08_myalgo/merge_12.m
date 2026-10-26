function merge_12()
%MERGE_12  Consolidate the twelve-instance sweep across every scheduling mode.
%
%   Reads every CSV in build/08_myalgo/results12/, concatenates them, and writes
%   two files:
%
%       merged_per_seed.csv   one row per (mode, instance, seed)
%       merged_summary.csv    one row per (mode, instance): mean and sd of vehicles
%                             and distance, plus how often the best-known vehicle
%                             count was reached
%
%   The robustness of the whole comparison rests on one check that is done here and
%   reported explicitly: whether the same (mode, instance, seed) appears twice with
%   different results.  If it does, the solver is still not deterministic and the
%   variances below cannot be used.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    addpath(fullfile(here, '..', '09_solvers'));
    d = fullfile(here, 'results12');
    if ~exist(d, 'dir'), error('no results12 directory'); end

    files = dir(fullfile(d, '*_part*.csv'));
    if isempty(files), error('no result files found'); end

    bks = load_bks();
    T = [];
    for k = 1:numel(files)
        f = fullfile(d, files(k).name);
        if dir(f).bytes <= 64, continue; end    % header only
        t = readtable(f, 'VariableNamingRule', 'preserve');
        if isempty(t), continue; end
        T = [T; t]; %#ok<AGROW>
    end
    if isempty(T), error('all result files are empty'); end

    fprintf('loaded %d rows from %d files\n', height(T), numel(files));

    % ---- determinism check
    [g, ~] = findgroups(T(:, {'instance', 'mode', 'seed'}));
    nDup = 0;
    for i = 1:max(g)
        m = (g == i);
        if sum(m) > 1
            if numel(unique(T.dist(m))) > 1 || numel(unique(T.veh(m))) > 1
                nDup = nDup + 1;
            end
        end
    end
    fprintf('repeated (instance, mode, seed) groups with differing results: %d\n', nDup);
    if nDup > 0
        fprintf('  WARNING: the solver is still not deterministic; variances are unusable\n');
    else
        fprintf('  deterministic: no conflicting repeats\n');
    end

    T = sortrows(T, {'mode', 'instance', 'seed'});
    writetable(T, fullfile(d, 'merged_per_seed.csv'));

    % ---- per (mode, instance) summary
    modes = unique(T.mode);
    insts = unique(T.instance);
    rows = {};
    for a = 1:numel(modes)
        for b = 1:numel(insts)
            m = strcmp(T.mode, modes{a}) & strcmp(T.instance, insts{b});
            if ~any(m), continue; end
            bv = bks.(lower(insts{b})).routes;
            v = T.veh(m); dd = T.dist(m); gp = T.gap(m);
            rows(end+1, :) = {modes{a}, insts{b}, sum(m), ...
                              mean(v), std(v), min(v), ...
                              mean(dd), std(dd), min(dd), ...
                              mean(gp), ...
                              bv, sum(v == bv)}; %#ok<AGROW>
        end
    end
    S = cell2table(rows, 'VariableNames', ...
        {'mode','instance','n','vehMean','vehSd','vehMin', ...
         'distMean','distSd','distMin','gapMean','bksVeh','hitBKS'});
    writetable(S, fullfile(d, 'merged_summary.csv'));

    % ---- per-mode headline
    fprintf('\n%-12s %8s %10s %10s %10s %10s\n', ...
            'mode', 'runs', 'vehMean', 'distMean', 'gapMean', 'hitBKS/12');
    fprintf('%s\n', repmat('-', 1, 66));
    for a = 1:numel(modes)
        m = strcmp(T.mode, modes{a});
        bv = zeros(sum(m), 1); ii = find(m);
        for k = 1:numel(ii)
            bv(k) = bks.(lower(T.instance{ii(k)})).routes;
        end
        fprintf('%-12s %8d %10.2f %10.2f %10.2f %6d\n', modes{a}, sum(m), ...
                mean(T.veh(m)), mean(T.dist(m)), mean(T.gap(m)), sum(T.veh(m) == bv));
    end

    % ---- paired comparison, mode against mode
    fprintf('\npaired comparisons on (instance, seed):\n');
    for a = 1:numel(modes)
        for b = a+1:numel(modes)
            ma = strcmp(T.mode, modes{a});
            mb = strcmp(T.mode, modes{b});
            ka = strcat(T.instance(ma), "_", string(T.seed(ma)));
            kb = strcat(T.instance(mb), "_", string(T.seed(mb)));
            [common, ia, ib] = intersect(ka, kb);
            if numel(common) < 5, continue; end
            da = T.dist(ma); da = da(ia);
            db = T.dist(mb); db = db(ib);
            diffv = da - db;
            fprintf('  %-12s vs %-12s  n=%2d  mean diff %+8.2f  sd %7.2f\n', ...
                    modes{a}, modes{b}, numel(common), mean(diffv), std(diffv));
        end
    end

    fprintf('\nwrote merged_per_seed.csv and merged_summary.csv\n');
end
