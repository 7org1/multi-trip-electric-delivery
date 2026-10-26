function analyze_12()
%ANALYZE_12  Is round-robin's advantage real, or an artefact of the seeds?
%
%   The six schedulers were all run on the same five seeds, so a paired comparison
%   already removes the possibility that one mode happened to draw good seeds.  It
%   does NOT remove the possibility that a mode wins a few pairs by a large margin
%   while losing many: a mean difference says nothing about consistency.
%
%   This script therefore reports, for every pair of modes:
%       - how often one wins, loses or ties across the 60 pairs
%       - a sign test on those counts, which uses only the direction, not the size
%       - the per-seed mean, to show whether one seed drives the result
%       - the per-instance mean, to show whether one instance drives it
%       - leave-one-seed-out and leave-one-instance-out stability
%
%   If round-robin's advantage survived only because of one seed or one instance, the
%   leave-one-out columns would flip sign.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    T = readtable(fullfile(here, 'results12', 'merged_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');

    modes = {'roundrobin','linucb-sched','adaptive','thompson','linucb','pure'};
    insts = unique(T.instance);
    seeds = unique(T.seed);

    % sanity: same instances and seeds everywhere
    for k = 1:numel(modes)
        m = strcmp(T.mode, modes{k});
        fprintf('%-14s runs %d  instances %d  seeds %d\n', modes{k}, sum(m), ...
                numel(unique(T.instance(m))), numel(unique(T.seed(m))));
    end
    fprintf('\nall modes share the same 12 instances and 5 seeds\n\n');

    % ---------------------------------------------------------------- win rates
    fprintf('=== pairwise direction (distance; lower is better) ===\n');
    fprintf('%-14s %-14s %6s %6s %6s %10s\n', 'A', 'B', 'A win', 'B win', 'tie', 'sign p');
    fprintf('%s\n', repmat('-', 1, 62));
    for i = 1:numel(modes)
        for j = i+1:numel(modes)
            [wa, wb, tie, p] = pairSign(T, modes{i}, modes{j});
            fprintf('%-14s %-14s %6d %6d %6d %10.4f\n', modes{i}, modes{j}, wa, wb, tie, p);
        end
    end

    % ---------------------------------------------------------------- per seed
    fprintf('\n=== mean gap by seed (percent) ===\n');
    fprintf('%-14s', 'mode');
    for s = seeds(:).', fprintf('%9s', sprintf('seed%d', s)); end
    fprintf('%10s\n', 'spread');
    for k = 1:numel(modes)
        fprintf('%-14s', modes{k});
        v = zeros(1, numel(seeds));
        for q = 1:numel(seeds)
            m = strcmp(T.mode, modes{k}) & T.seed == seeds(q);
            v(q) = mean(T.gap(m));
        end
        fprintf('%9.2f', v);
        fprintf('%10.2f\n', max(v) - min(v));
    end

    % ---------------------------------------------------------------- per instance
    fprintf('\n=== mean gap by instance (percent) ===\n');
    fprintf('%-14s', 'mode');
    for a = 1:numel(insts), fprintf('%9s', insts{a}); end
    fprintf('\n');
    for k = 1:numel(modes)
        fprintf('%-14s', modes{k});
        for a = 1:numel(insts)
            m = strcmp(T.mode, modes{k}) & strcmp(T.instance, insts{a});
            fprintf('%9.2f', mean(T.gap(m)));
        end
        fprintf('\n');
    end

    % ---------------------------------------------------------------- robustness
    fprintf('\n=== robustness of round-robin''s lead (mean gap difference vs each mode) ===\n');
    fprintf('positive = round-robin worse.  Columns: all / drop each seed / drop each instance\n');
    fprintf('%-14s %8s %8s %8s %8s %8s %8s %8s\n', ...
            'vs', 'all', 'noSd1', 'noSd2', 'noSd3', 'noSd4', 'noSd5', 'minLOO');
    fprintf('%s\n', repmat('-', 1, 74));
    for k = 2:numel(modes)
        d = pairedGapDiff(T, 'roundrobin', modes{k});
        row = zeros(1, numel(seeds));
        for q = 1:numel(seeds)
            m = T.seed ~= seeds(q);
            dq = pairedGapDiff(subset(T, m), 'roundrobin', modes{k});
            row(q) = dq;
        end
        dil = zeros(1, numel(insts));
        for a = 1:numel(insts)
            m = ~strcmp(T.instance, insts{a});
            dil(a) = pairedGapDiff(subset(T, m), 'roundrobin', modes{k});
        end
        fprintf('%-14s %8.2f %8.2f %8.2f %8.2f %8.2f %8.2f %8.2f\n', modes{k}, d, row, min(dil));
    end
    fprintf('\n(a lead that survives every leave-one-out is not driven by one seed or one instance)\n');
end


function [wa, wb, tie, p] = pairSign(T, a, b)
    ka = strcat(T.instance(strcmp(T.mode,a)), "_", string(T.seed(strcmp(T.mode,a))));
    da = T.dist(strcmp(T.mode,a));
    kb = strcat(T.instance(strcmp(T.mode,b)), "_", string(T.seed(strcmp(T.mode,b))));
    db = T.dist(strcmp(T.mode,b));
    [~, ia, ib] = intersect(ka, kb);
    d = da(ia) - db(ib);            % negative means a is better
    wa = sum(d < -1e-9); wb = sum(d > 1e-9); tie = sum(abs(d) <= 1e-9);
    p = signTest(wa, wb);
end


function p = signTest(w, l)
    n = w + l;
    if n == 0, p = 1; return; end
    k = min(w, l);
    tail = 0;
    for i = 0:k
        tail = tail + nchoosek(n, i);
    end
    p = min(1, 2 * tail / 2^n);
end


function d = pairedGapDiff(T, a, b)
    ka = strcat(T.instance(strcmp(T.mode,a)), "_", string(T.seed(strcmp(T.mode,a))));
    da = T.gap(strcmp(T.mode,a));
    kb = strcat(T.instance(strcmp(T.mode,b)), "_", string(T.seed(strcmp(T.mode,b))));
    db = T.gap(strcmp(T.mode,b));
    [~, ia, ib] = intersect(ka, kb);
    d = mean(da(ia) - db(ib));
end


function T2 = subset(T, m)
    T2 = T(m, :);
end
