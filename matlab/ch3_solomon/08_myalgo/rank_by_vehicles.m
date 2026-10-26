function rank_by_vehicles()
%RANK_BY_VEHICLES  Compare the methods on vehicle count only.
%
%   WHY THIS IS THE RIGHT CRITERION
%   Vehicles are the first component of the objective.  Distance is only a tiebreak,
%   and using it inside the comparison means a method that spends vehicles to shorten
%   routes can look good.  Here the only question asked of each pair is: did this
%   method use fewer vehicles?  Same count is a tie, fewer is a win, nothing else
%   counts.
%
%   TWO TESTS
%   Pairwise  -- wins, losses and ties for every pair of methods across the 60
%                (instance, seed) blocks, with an exact sign test on the decisive pairs.
%   Friedman  -- the standard non-parametric test for K methods over N blocks, with
%                the tie correction, on ranks formed from the vehicle counts alone.
%                This is the test to quote when a reviewer asks whether the five
%                methods differ at all.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    B = readtable(fullfile(here, '..', '09_solvers', 'results', 'all_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');
    M = readtable(fullfile(here, 'results12', 'merged_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');
    L = M(strcmp(M.mode, 'linucb-sched'), :);

    methods = {'ALNS','VNS','Tabu','GA','LinUCB-sched'};
    K = numel(methods);
    insts = unique(B.instance);
    seeds = (1:5).';
    N = numel(insts) * numel(seeds);

    % ---- build the block matrix: rows = (instance, seed), cols = method, values = vehicles
    V = nan(N, K);
    blk = cell(N, 1);
    r = 0;
    for a = 1:numel(insts)
        for s = seeds.'
            r = r + 1;
            blk{r} = sprintf('%s_s%d', insts{a}, s);
            for k = 1:K
                if strcmp(methods{k}, 'LinUCB-sched')
                    m = strcmp(L.instance, insts{a}) & L.seed == s;
                    V(r, k) = L.veh(m);
                else
                    m = strcmp(B.method, methods{k}) & strcmp(B.instance, insts{a}) & B.seed == s;
                    V(r, k) = B.veh(m);
                end
            end
        end
    end
    assert(~any(isnan(V(:))), 'some block is missing a value');

    % ---------------------------------------------------------------- descriptives
    fprintf('=== vehicle counts, mean over the %d blocks ===\n', N);
    fprintf('%-14s %10s %10s %10s\n', 'method', 'meanVeh', 'totalVeh', 'bestBlocks');
    fprintf('%s\n', repmat('-', 1, 48));
    for k = 1:K
        fprintf('%-14s %10.3f %10.1f %10d\n', methods{k}, mean(V(:, k)), ...
                sum(V(:, k)), sum(V(:, k) == min(V, [], 2)));
    end

    % ---------------------------------------------------------------- pairwise
    fprintf('\n=== pairwise on vehicles only: fewer wins, equal ties ===\n');
    fprintf('%-14s %-14s %6s %6s %6s %10s\n', 'A', 'B', 'A win', 'B win', 'tie', 'sign p');
    fprintf('%s\n', repmat('-', 1, 62));
    for i = 1:K
        for j = i+1:K
            wa = sum(V(:, i) < V(:, j));
            wb = sum(V(:, i) > V(:, j));
            t  = sum(V(:, i) == V(:, j));
            fprintf('%-14s %-14s %6d %6d %6d %10.4f\n', ...
                    methods{i}, methods{j}, wa, wb, t, signTest(wa, wb));
        end
    end

    % ---------------------------------------------------------------- Friedman
    fprintf('\n=== Friedman test on vehicle counts ===\n');
    R = zeros(N, K);
    tieSum = 0;
    for i = 1:N
        % ranks with ties averaged, and the tie-group sizes accumulated for the
        % Friedman correction factor
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
    df = K - 1;
    p = 1 - chi2cdf(Q, df);

    fprintf('  N blocks %d, K methods %d\n', N, K);
    fprintf('  mean ranks (lower is better):\n');
    for k = 1:K
        fprintf('    %-14s %6.3f\n', methods{k}, Rbar(k));
    end
    fprintf('  Q = %.3f  df = %d  p = %.4g\n', Q, df, p);
    if p < 0.05
        fprintf('  VERDICT: the five methods differ significantly on vehicle count\n');
    else
        fprintf('  VERDICT: no significant difference on vehicle count\n');
    end

    % ---------------------------------------------------------------- LinUCB-sched focus
    fprintf('\n=== LinUCB-sched against each baseline, vehicles only ===\n');
    fprintf('%-14s %8s %8s %8s %6s %10s %10s\n', ...
            'baseline', 'L fewer', 'B fewer', 'tie', 'n', 'sign p', 'meanDiff');
    fprintf('%s\n', repmat('-', 1, 74));
    kk = find(strcmp(methods, 'LinUCB-sched'));
    for k = 1:K
        if k == kk, continue; end
        w = sum(V(:, kk) < V(:, k));
        l = sum(V(:, kk) > V(:, k));
        t = sum(V(:, kk) == V(:, k));
        fprintf('%-14s %8d %8d %8d %6d %10.4f %+10.2f\n', ...
                methods{k}, w, l, t, w + l, signTest(w, l), mean(V(:, kk) - V(:, k)));
    end
    fprintf('\n(meanDiff negative means LinUCB-sched used fewer vehicles)\n');
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
