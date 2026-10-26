function analyze_lexico()
%ANALYZE_LEXICO  Compare the six schedulers on the actual objective, not on distance.
%
%   WHY THE EARLIER RANKING WAS WRONG
%   Ranking by distance gap alone is misleading here, because the instances differ
%   enormously in how far the fleet is from the best known.  On r2_2_1 the best known
%   is 4 vehicles at 4483 km, and every method returns about 7 vehicles at 3850 km: a
%   negative distance gap, i.e. "better than the best known", for a solution that is
%   three vehicles worse.  Any ranking built on distance alone therefore rewards
%   spending vehicles.
%
%   The objective in this thesis is lexicographic: fewer vehicles first, then shorter
%   distance.  This script therefore compares, for every (instance, seed), which mode
%   produces the lexicographically best solution, and reports:
%       - how often each mode is the unique winner or ties for best
%       - the fleet total, which is the first-order criterion
%       - the distance comparison restricted to pairs where the fleets are equal,
%         which is the only situation where distance decides anything
%       - a sign test on the pairwise lexicographic wins

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    T = readtable(fullfile(here, 'results12', 'merged_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');

    modes = {'roundrobin','linucb-sched','adaptive','thompson','linucb','pure'};
    insts = unique(T.instance);
    seeds = unique(T.seed);

    % ---------------------------------------------------------------- fleet
    fprintf('=== fleet total over 12 instances (lower is better; first criterion) ===\n');
    bks = load_bks();
    tot = 0;
    for a = 1:numel(insts), tot = tot + bks.(lower(insts{a})).routes; end
    fprintf('%-14s %10s %10s\n', 'mode', 'fleet', 'vs BKS');
    fprintf('%-14s %10d %+10d\n', 'BKS', tot, 0);
    fleet = zeros(1, numel(modes));
    for k = 1:numel(modes)
        m = strcmp(T.mode, modes{k});
        fleet(k) = sum(T.veh(m)) / numel(seeds);
        fprintf('%-14s %10.2f %+10.2f\n', modes{k}, fleet(k), fleet(k) - tot);
    end

    % ---------------------------------------------------------------- winners
    fprintf('\n=== lexicographic winners across the 60 (instance, seed) pairs ===\n');
    win = zeros(1, numel(modes));
    for a = 1:numel(insts)
        for s = seeds(:).'
            v = zeros(1, numel(modes)); d = zeros(1, numel(modes));
            for k = 1:numel(modes)
                m = strcmp(T.mode, modes{k}) & strcmp(T.instance, insts{a}) & T.seed == s;
                v(k) = T.veh(m); d(k) = T.dist(m);
            end
            % lexicographic best
            bestV = min(v);
            cand = find(v == bestV);
            [~, j] = min(d(cand));
            win(cand(j)) = win(cand(j)) + 1;
        end
    end
    for k = 1:numel(modes)
        fprintf('  %-14s %3d / 60\n', modes{k}, win(k));
    end

    % ---------------------------------------------------------------- distance only when fleets tie
    fprintf('\n=== distance comparison, restricted to equal-fleet pairs ===\n');
    fprintf('%-14s %-14s %6s %6s %6s %10s\n', 'A', 'B', 'A win', 'B win', 'n', 'sign p');
    fprintf('%s\n', repmat('-', 1, 62));
    for i = 1:numel(modes)
        for j = i+1:numel(modes)
            [wa, wb, n] = tieFleetCompare(T, modes{i}, modes{j});
            if n < 5
                fprintf('%-14s %-14s %6d %6d %6d %10s\n', modes{i}, modes{j}, wa, wb, n, 'too few');
                continue
            end
            fprintf('%-14s %-14s %6d %6d %6d %10.4f\n', modes{i}, modes{j}, wa, wb, n, ...
                    signTest(wa, wb));
        end
    end

    % ---------------------------------------------------------------- per instance fleet
    fprintf('\n=== fleet by instance (mean over 5 seeds) with BKS ===\n');
    fprintf('%-14s', 'mode');
    for a = 1:numel(insts), fprintf('%9s', insts{a}); end
    fprintf('\n');
    fprintf('%-14s', 'BKS');
    for a = 1:numel(insts), fprintf('%9d', bks.(lower(insts{a})).routes); end
    fprintf('\n');
    for k = 1:numel(modes)
        fprintf('%-14s', modes{k});
        for a = 1:numel(insts)
            m = strcmp(T.mode, modes{k}) & strcmp(T.instance, insts{a});
            fprintf('%9.1f', mean(T.veh(m)));
        end
        fprintf('\n');
    end
end


function [wa, wb, n] = tieFleetCompare(T, a, b)
%TIEFLEETCOMPARE  Distance wins only on pairs where both modes used the same fleet.
    ka = strcat(T.instance(strcmp(T.mode,a)), "_", string(T.seed(strcmp(T.mode,a))));
    va = T.veh(strcmp(T.mode,a));  da = T.dist(strcmp(T.mode,a));
    kb = strcat(T.instance(strcmp(T.mode,b)), "_", string(T.seed(strcmp(T.mode,b))));
    vb = T.veh(strcmp(T.mode,b));  db = T.dist(strcmp(T.mode,b));
    [~, ia, ib] = intersect(ka, kb);
    same = va(ia) == vb(ib);
    d = da(ia(same)) - db(ib(same));
    wa = sum(d < -1e-9); wb = sum(d > 1e-9); n = numel(d);
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
