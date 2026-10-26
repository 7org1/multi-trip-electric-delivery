function analyze_variants()
%ANALYZE_VARIANTS  Compare the three balance variants against the existing schedulers.
%
%   WHAT THE VARIANTS ARE FOR
%   LinUCB-sched was found to be behaviourally identical to uniform rotation, because
%   the theoretical exploration width kept the bonus 50-130 times larger than the
%   value term for the whole run.  Three fixes were run, each removing that domination
%   a different way:
%
%       V1  rewardScale 50     the value term is scaled up
%       V2  alphaDecay fast    the bonus decays as 1/n instead of sqrt(ln t / n)
%       V3  standardise        both terms normalised, alpha = 0.5
%
%   THE PREDICTION, WRITTEN BEFORE SEEING THE RESULT
%   A 70-second pilot gave operator shares of 5/65/29, 0.6/91/8 and 36/29/35 per cent.
%   V2 therefore collapses onto one arm, which is close to the "pure" control that
%   measured 154.0 vehicles, so V2 should be worse than round-robin.  V3 is near
%   uniform, so it should land close to round-robin.  V1 sits between them.  If none
%   of the three beats round-robin, the balance of exploration was not the binding
%   constraint and the learning line should be dropped.
%
%   Reported: fleet totals (the first criterion), lexicographic winners, a Friedman
%   test on vehicle counts, and pairwise sign tests against round-robin.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    T = readtable(fullfile(here, 'results12', 'merged_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');

    all = unique(T.mode);
    fprintf('modes present: %s\n\n', strjoin(cellstr(all).', ', '));

    order = {'pure','roundrobin','adaptive','thompson','linucb','linucb-sched', ...
             'linucb_v1_reward50','linucb_v2_fastdecay','linucb_v3_standard'};
    order = order(ismember(order, cellstr(all)));

    insts = unique(T.instance);
    seeds = unique(T.seed);

    % ---------------------------------------------------------------- fleet
    fprintf('=== fleet total over 12 instances (lower is better) ===\n');
    fprintf('%-24s %10s %12s %10s\n', 'mode', 'fleet', 'meanGap%', 'bestBlocks');
    fprintf('%s\n', repmat('-', 1, 60));
    for k = 1:numel(order)
        m = strcmp(T.mode, order{k});
        fleet = sum(T.veh(m)) / numel(seeds);
        fprintf('%-24s %10.2f %12.2f %10d\n', order{k}, fleet, ...
                mean(T.gap(m)), numBestBlocks(T, order, order{k}));
    end

    % ---------------------------------------------------------------- Friedman
    fprintf('\n=== Friedman on vehicle counts over %d blocks, %d modes ===\n', ...
            numel(insts)*numel(seeds), numel(order));
    V = buildBlocks(T, order, insts, seeds);
    [Q, p, Rbar] = friedman(V);
    for k = 1:numel(order)
        fprintf('    %-24s mean rank %6.3f\n', order{k}, Rbar(k));
    end
    fprintf('    Q = %.3f, df = %d, p = %.4g\n', Q, numel(order)-1, p);

    % ---------------------------------------------------------------- vs roundrobin
    if any(strcmp(order, 'roundrobin'))
        fprintf('\n=== each mode against round-robin, vehicles only ===\n');
        fprintf('%-24s %8s %8s %8s %10s %10s\n', 'mode', 'fewer', 'more', 'tie', 'sign p', 'meanDiff');
        fprintf('%s\n', repmat('-', 1, 72));
        kr = find(strcmp(order, 'roundrobin'));
        for k = 1:numel(order)
            if k == kr, continue; end
            w = sum(V(:, k) < V(:, kr));
            l = sum(V(:, k) > V(:, kr));
            t = sum(V(:, k) == V(:, kr));
            fprintf('%-24s %8d %8d %8d %10.4f %+10.2f\n', order{k}, w, l, t, ...
                    signTest(w, l), mean(V(:, k) - V(:, kr)));
        end
        fprintf('\n(fewer/more are from the mode%s perspective; negative meanDiff = fewer vehicles)\n', '');
    end
end


function nb = numBestBlocks(T, order, mode)
    insts = unique(T.instance); seeds = unique(T.seed);
    V = buildBlocks(T, order, insts, seeds);
    k = find(strcmp(order, mode));
    nb = sum(V(:, k) == min(V, [], 2));
end


function V = buildBlocks(T, order, insts, seeds)
    N = numel(insts) * numel(seeds);
    K = numel(order);
    V = nan(N, K);
    r = 0;
    for a = 1:numel(insts)
        for s = seeds(:).'
            r = r + 1;
            for k = 1:K
                m = strcmp(T.mode, order{k}) & strcmp(T.instance, insts{a}) & T.seed == s;
                if any(m), V(r, k) = T.veh(find(m, 1)); end
            end
        end
    end
end


function [Q, p, Rbar] = friedman(V)
    [N, K] = size(V);
    R = zeros(N, K);
    tieSum = 0;
    for i = 1:N
        [sv, ord] = sort(V(i, :));
        rr = zeros(1, K);
        g = 1;
        while g <= K
            h = g;
            while h < K && sv(h+1) == sv(g), h = h + 1; end
            rr(ord(g:h)) = (g + h) / 2;
            tieSum = tieSum + (h - g + 1)^3 - (h - g + 1);
            g = h + 1;
        end
        R(i, :) = rr;
    end
    Rbar = mean(R, 1);
    Q = 12 * N / (K * (K + 1)) * sum(Rbar.^2) - 3 * N * (K + 1);
    corr = 1 - tieSum / (N * (K^3 - K));
    if corr > 0, Q = Q / corr; end
    p = 1 - chi2cdf(Q, K - 1);
end


function p = signTest(w, l)
    n = w + l;
    if n == 0, p = 1; return; end
    k = min(w, l);
    tail = 0;
    for i = 0:k, tail = tail + nchoosek(n, i); end
    p = min(1, 2 * tail / 2^n);
end
