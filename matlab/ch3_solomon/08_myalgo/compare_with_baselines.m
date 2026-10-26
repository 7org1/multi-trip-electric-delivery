function compare_with_baselines()
%COMPARE_WITH_BASELINES  LinUCB-sched against the four orthodox solvers.
%
%   The four baselines were run earlier on the same twelve instances, the same five
%   seeds and the same 300 s CPU budget, and their per-seed results are on disk.  This
%   script puts them side by side with the LinUCB-sched scheduler and reports the
%   comparison the thesis actually needs: the lexicographic objective, vehicles first.
%
%   WHY NOT JUST AVERAGE THE DISTANCE GAP
%   Because on r2_2_1 the best known is 4 vehicles at 4483 km while every method in
%   this project returns about 7 vehicles at 3850 km.  Averaging distance gaps rewards
%   that, even though it is three vehicles worse.  Everything below is therefore
%   reported as (vehicles, then distance) and the win counts use the same order.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    B = readtable(fullfile(here, '..', '09_solvers', 'results', 'all_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');
    M = readtable(fullfile(here, 'results12', 'merged_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');

    % keep only LinUCB-sched from the new sweep, and rename for the join
    L = M(strcmp(M.mode, 'linucb-sched'), :);
    L.method = repmat("LinUCB-sched", height(L), 1);

    insts = unique(B.instance);
    bks = load_bks();

    methods = {'ALNS','VNS','Tabu','GA','LinUCB-sched'};

    % ---------------------------------------------------------------- per instance
    fprintf('=== mean over 5 seeds: vehicles / distance ===\n');
    fprintf('%-9s %8s', 'instance', 'BKS');
    for k = 1:numel(methods), fprintf(' %16s', methods{k}); end
    fprintf('\n');
    fprintf('%s\n', repmat('-', 1, 9 + 8 + 17*numel(methods)));

    for a = 1:numel(insts)
        b = bks.(lower(insts{a}));
        fprintf('%-9s %3d/%-4.0f', insts{a}, b.routes, b.dist);
        for k = 1:numel(methods)
            [v, d] = pick(B, L, methods{k}, insts{a});
            fprintf(' %7.1f/%-8.0f', v, d);
        end
        fprintf('\n');
    end

    % ---------------------------------------------------------------- summary
    fprintf('\n=== summary over 12 instances x 5 seeds ===\n');
    fprintf('%-14s %10s %12s %12s %12s\n', ...
            'method', 'fleet', 'meanDist', 'meanGap%', 'atBKSfleet');
    fprintf('%s\n', repmat('-', 1, 64));
    totBKS = 0;
    for a = 1:numel(insts), totBKS = totBKS + bks.(lower(insts{a})).routes; end
    fprintf('%-14s %10.1f %12s %12s %12s\n', 'BKS', totBKS, '-', '0', '-');

    for k = 1:numel(methods)
        fleet = 0; dist = 0; gap = 0; hit = 0; n = 0;
        for a = 1:numel(insts)
            b = bks.(lower(insts{a}));
            [v, d, ~, g, h] = pick(B, L, methods{k}, insts{a});
            fleet = fleet + v; dist = dist + d; gap = gap + g; hit = hit + h; n = n + 5;
        end
        fprintf('%-14s %10.1f %12.1f %12.2f %9d/%-3d\n', ...
                methods{k}, fleet, dist/numel(insts), gap/numel(insts), hit, n);
    end

    % ---------------------------------------------------------------- head to head
    fprintf('\n=== LinUCB-sched vs each baseline, lexicographic, on the 60 pairs ===\n');
    fprintf('%-14s %8s %8s %8s %10s\n', 'baseline', 'L wins', 'B wins', 'tie', 'sign p');
    fprintf('%s\n', repmat('-', 1, 54));
    for k = 1:4
        [w, l, t, p] = headToHead(B, L, methods{k});
        fprintf('%-14s %8d %8d %8d %10.4f\n', methods{k}, w, l, t, p);
    end

    fprintf('\n(w = LinUCB-sched better, l = baseline better, lexicographic)\n');
end


function [v, d, n5, g, hit] = pick(B, L, method, inst)
    if strcmp(method, 'LinUCB-sched')
        m = strcmp(L.instance, inst);
        v = mean(L.veh(m)); d = mean(L.dist(m)); g = mean(L.gap(m));
        n5 = sum(m);
        bks = load_bks(); bks = bks.(lower(inst));
        hit = sum(L.veh(m) == bks.routes);
    else
        m = strcmp(B.method, method) & strcmp(B.instance, inst);
        v = mean(B.veh(m)); d = mean(B.dist(m)); g = mean(B.gapPct(m));
        n5 = sum(m);
        bks = load_bks(); bks = bks.(lower(inst));
        hit = sum(B.veh(m) == bks.routes);
    end
end


function [w, l, t, p] = headToHead(B, L, method)
    w = 0; l = 0; t = 0;
    insts = unique(L.instance);
    for a = 1:numel(insts)
        for s = 1:5
            ml = strcmp(L.instance, insts{a}) & L.seed == s;
            mb = strcmp(B.instance, insts{a}) & B.seed == s & strcmp(B.method, method);
            if ~any(ml) || ~any(mb), continue; end
            vl = L.veh(ml); dl = L.dist(ml);
            vb = B.veh(mb); db = B.dist(mb);
            if vl < vb || (vl == vb && dl < db - 1e-9)
                w = w + 1;
            elseif vb < vl || (vb == vl && db < dl - 1e-9)
                l = l + 1;
            else
                t = t + 1;
            end
        end
    end
    n = w + l;
    if n == 0, p = 1; return; end
    k = min(w, l); tail = 0;
    for i = 0:k, tail = tail + nchoosek(n, i); end
    p = min(1, 2*tail/2^n);
end
