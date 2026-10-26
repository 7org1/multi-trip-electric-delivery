function peek_variants()
%PEEK_VARIANTS  Fleet totals for whatever variant files are complete so far.
%
%   Reads the raw per-part CSVs rather than the merged file, so an unfinished
%   variant does not contaminate the merged tables.  Any variant with fewer than the
%   expected rows is reported as partial and excluded from the verdict.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    d = fullfile(here, 'results12');

    bks = load_bks();
    insts = {'c1_2_1','c1_2_4','c2_2_1','c2_2_4','r1_2_1','r1_2_4', ...
             'r2_2_1','r2_2_4','rc1_2_1','rc1_2_4','rc2_2_1','rc2_2_4'};

    variants = {'linucb_v1_reward50','linucb_v2_fastdecay','linucb_v3_standard'};
    refs = {'roundrobin','adaptive','linucb','linucb-sched','thompson','pure'};

    fprintf('%-24s %6s %10s %12s %12s\n', 'variant', 'runs', 'fleet', 'meanGap%', 'status');
    fprintf('%s\n', repmat('-', 1, 68));

    allRows = {};
    for v = 1:numel(variants)
        V = readVariant(d, variants{v});
        n = height(V);
        st = ternary(n >= 60, 'complete', sprintf('PARTIAL %d/60', n));
        if n == 0, continue; end
        fleet = sum(V.veh) / 5;
        fprintf('%-24s %6d %10.2f %12.2f %12s\n', variants{v}, n, fleet, mean(V.gap), st);
        allRows{end+1} = V; %#ok<AGROW>
    end

    fprintf('\n--- reference modes (already complete) ---\n');
    M = readtable(fullfile(d, 'merged_per_seed.csv'), 'VariableNamingRule', 'preserve');
    for r = 1:numel(refs)
        m = strcmp(M.mode, refs{r});
        if ~any(m), continue; end
        fprintf('%-24s %6d %10.2f %12.2f %12s\n', refs{r}, sum(m), ...
                sum(M.veh(m))/5, mean(M.gap(m)), 'complete');
    end

    fprintf('\nBKS fleet total: %d\n', sumCell(bks, insts));
end


function V = readVariant(d, name)
    V = [];
    for p = 1:3
        f = fullfile(d, sprintf('%s_part%d.csv', name, p));
        if ~exist(f, 'file') || dir(f).bytes <= 64, continue; end
        t = readtable(f, 'VariableNamingRule', 'preserve');
        V = [V; t]; %#ok<AGROW>
    end
end


function s = sumCell(bks, insts)
    s = 0;
    for a = 1:numel(insts), s = s + bks.(lower(insts{a})).routes; end
end


function o = ternary(c, a, b)
    if c, o = a; else, o = b; end
end
