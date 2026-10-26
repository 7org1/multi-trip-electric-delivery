function show_results()
%SHOW_RESULTS  Per-instance view of all nine schedulers, plus where they differ.
%
%   The summary table hides the structure: on some instances every scheduler returns
%   the same fleet, and on others they differ.  The last table below isolates the
%   blocks where the schedulers actually disagree, because that is the only place any
%   claim about scheduling can come from.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    T = readtable(fullfile(here, 'results12', 'merged_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');
    bks = load_bks();

    insts = {'c1_2_1','c1_2_4','c2_2_1','c2_2_4','r1_2_1','r1_2_4', ...
             'r2_2_1','r2_2_4','rc1_2_1','rc1_2_4','rc2_2_1','rc2_2_4'};
    modes = {'pure','roundrobin','adaptive','thompson','linucb', ...
             'linucb-sched','linucb_v1_reward50','linucb_v2_fastdecay','linucb_v3_standard'};
    short = {'pure','RR','adapt','TS','UCB','UCBsch','V1','V2','V3'};

    % ---------------------------------------------------------------- vehicles
    fprintf('=== mean vehicles over 5 seeds ===\n');
    fprintf('%-9s %5s', 'instance', 'BKS');
    for k = 1:numel(modes), fprintf('%7s', short{k}); end
    fprintf('%8s\n', 'spread');
    fprintf('%s\n', repmat('-', 1, 9 + 5 + 7*numel(modes) + 8));
    for a = 1:numel(insts)
        b = bks.(lower(insts{a}));
        fprintf('%-9s %5d', insts{a}, b.routes);
        v = zeros(1, numel(modes));
        for k = 1:numel(modes)
            m = strcmp(T.mode, modes{k}) & strcmp(T.instance, insts{a});
            v(k) = mean(T.veh(m));
            fprintf('%7.1f', v(k));
        end
        fprintf('%8.1f\n', max(v) - min(v));
    end

    % ---------------------------------------------------------------- gap
    fprintf('\n=== mean gap %% over 5 seeds ===\n');
    fprintf('%-9s %5s', 'instance', '');
    for k = 1:numel(modes), fprintf('%7s', short{k}); end
    fprintf('\n');
    for a = 1:numel(insts)
        fprintf('%-9s %5s', insts{a}, '');
        for k = 1:numel(modes)
            m = strcmp(T.mode, modes{k}) & strcmp(T.instance, insts{a});
            fprintf('%7.1f', mean(T.gap(m)));
        end
        fprintf('\n');
    end

    % ---------------------------------------------------------------- where they differ
    fprintf('\n=== blocks where the nine schedulers disagree on vehicle count ===\n');
    insts2 = unique(T.instance);
    seeds = unique(T.seed);
    nDiff = 0; nSame = 0;
    for a = 1:numel(insts2)
        for s = seeds(:).'
            v = zeros(1, numel(modes));
            for k = 1:numel(modes)
                m = strcmp(T.mode, modes{k}) & strcmp(T.instance, insts2{a}) & T.seed == s;
                v(k) = T.veh(m);
            end
            if max(v) > min(v)
                nDiff = nDiff + 1;
            else
                nSame = nDiff + 0; nSame = nSame; %#ok<NASGU>
                nSame = 0;
            end
        end
    end
    nTot = numel(insts2) * numel(seeds);
    fprintf('  %d of %d blocks show any disagreement; %d are identical for all nine\n', ...
            nDiff, nTot, nTot - nDiff);

    % per instance: how often do they disagree
    fprintf('\n  by instance:\n');
    for a = 1:numel(insts2)
        c = 0;
        for s = seeds(:).'
            v = zeros(1, numel(modes));
            for k = 1:numel(modes)
                m = strcmp(T.mode, modes{k}) & strcmp(T.instance, insts2{a}) & T.seed == s;
                v(k) = T.veh(m);
            end
            if max(v) > min(v), c = c + 1; end
        end
        if c > 0
            fprintf('    %-9s %d / 5 seeds differ\n', insts2{a}, c);
        end
    end
end
