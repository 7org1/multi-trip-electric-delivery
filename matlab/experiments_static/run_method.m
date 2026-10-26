function out = run_method(C, method, budget, seed, alphaMode)
% RUN_METHOD  One solver, one run, one budget.
%
%   The destroy-and-repair engine, the repair and the acceptance rule are shared by
%   every method, so that the comparison isolates the operator policy alone.
%
%   CBLNS  contextual bandit, the method of Chapter 3
%   ALNS   adaptive weights with roulette selection
%   VNS    deterministic cycling with growing size
%   Tabu   random destruction with a tabu tenure on the removed points
%   GA     a population, trip based crossover, mutation by destruction

if nargin < 3, budget = 60; end
if nargin < 4, seed = 1; end
rng(seed, 'twister');
out.name = method;

if strcmpi(method, 'CBLNS')
    if nargin < 5, alphaMode = 'decay'; end
    out = cblns_v3(C, budget, seed, alphaMode);
    return
end

% initial solution, the same for every method
order = 2:C.n;
[~, ord] = sort(C.D(1, order), 'descend');
trips = {};
[trips, ok] = insert_all(C, trips, order(ord));
if ~ok, error('the initial solution is infeasible'); end

t0 = tic; it = 0;

switch upper(method)
    case 'ALNS'
        w = ones(1, 3); sc = zeros(1, 3); used = zeros(1, 3);
        modes = {'sector', 'worst', 'random'};
        [curF, ~] = sol_cost(C, trips);
        best = trips; bestF = curF;
        while toc(t0) < budget
            it = it + 1;
            r = rand * sum(w); a = 1;
            while a < 3 && r > w(a), r = r - w(a); a = a + 1; end
            used(a) = used(a) + 1;
            [removed, partial] = destroy(C, trips, modes{a}, 6 + floor(rand * 9));
            if isempty(removed), continue, end
            [cand, ok] = insert_all(C, partial, removed);
            if ~ok, continue, end
            [f, ~] = sol_cost(C, cand);
            if f < curF - 1e-9
                trips = cand; curF = f; sc(a) = sc(a) + 1;
                if f < bestF - 1e-9, best = cand; bestF = f; end
            end
            if mod(it, 100) == 0
                for k = 1:3
                    if used(k) > 0
                        w(k) = max(0.2, 0.8 * w(k) + 0.2 * (sc(k) / used(k) + 0.05));
                    end
                end
                sc = zeros(1, 3); used = zeros(1, 3);
            end
        end
        out.trips = best; out.obj = bestF;

    case 'VNS'
        modes = {'sector', 'worst', 'random'};
        sizes = [6 10 16];
        [curF, ~] = sol_cost(C, trips);
        best = trips; bestF = curF;
        k = 1;
        while toc(t0) < budget
            it = it + 1;
            a = mod(k - 1, 3) + 1;
            [removed, partial] = destroy(C, trips, modes{a}, sizes(a));
            k = k + 1;
            if isempty(removed), continue, end
            [cand, ok] = insert_all(C, partial, removed);
            if ~ok, continue, end
            [f, ~] = sol_cost(C, cand);
            if f < curF - 1e-9
                trips = cand; curF = f;
                if f < bestF - 1e-9, best = cand; bestF = f; end
            end
        end
        out.trips = best; out.obj = bestF;

    case 'TABU'
        tenure = 15; tabuUntil = containers.Map('KeyType', 'double', 'ValueType', 'double');
        [curF, ~] = sol_cost(C, trips);
        best = trips; bestF = curF;
        while toc(t0) < budget
            it = it + 1;
            [removed, partial] = destroy(C, trips, 'random', 6 + floor(rand * 9));
            if isempty(removed), continue, end
            % a point that is still tabu may not be reinserted
            free = removed;
            if ~isempty(tabuUntil)
                free = removed(~cellfun(@(c) isKey(tabuUntil, c) && tabuUntil(c) > it, num2cell(removed)));
            end
            if numel(free) < numel(removed)
                [partial, ok] = insert_all(C, partial, setdiff(removed, free));
                if ~ok, continue, end
            end
            [cand, ok] = insert_all(C, partial, free);
            if ~ok, continue, end
            [f, ~] = sol_cost(C, cand);
            if f < curF + 1e-9 || f < bestF - 1e-9
                trips = cand; curF = f;
                for c = removed, tabuUntil(c) = it + tenure; end
                if f < bestF - 1e-9, best = cand; bestF = f; end
            end
        end
        out.trips = best; out.obj = bestF;

    case 'GA'
        P = cell(1, 12); F = zeros(1, 12);
        for i = 1:12
            cand = trips; F(i) = sol_cost(C, cand);
            P{i} = cand;
        end
        [bestF, ib] = min(F); best = P{ib};
        while toc(t0) < budget
            it = it + 1;
            i = randi(12); j = randi(12);
            if F(i) > F(j), tmp = i; i = j; j = tmp; end
            child = {};
            for k = 1:numel(P{i})
                if rand < 0.6, child{end+1} = P{i}{k}; end %#ok<AGROW>
            end
            cover = false(C.n, 1);
            for k = 1:numel(child), cover(child{k}) = true; end
            for k = 1:numel(P{j})
                rest = P{j}{k}(~cover(P{j}{k}));
                if ~isempty(rest)
                    child{end+1} = rest; %#ok<AGROW>
                    cover(rest) = true;
                end
            end
            missing = find(~cover(2:end))' + 1;
            if ~isempty(missing)
                [child, ok] = insert_all(C, child, missing);
                if ~ok, continue, end
            end
            if rand < 0.7
                modes = {'sector', 'worst', 'random'};
                [removed, partial] = destroy(C, child, modes{randi(3)}, 6 + floor(rand * 9));
                if ~isempty(removed)
                    [child, ok] = insert_all(C, partial, removed);
                    if ~ok, continue, end
                end
            end
            cf = sol_cost(C, child);
            [~, wv] = max(F);
            if cf < F(wv)
                P{wv} = child; F(wv) = cf;
                if cf < bestF - 1e-9, best = child; bestF = cf; end
            end
        end
        out.trips = best; out.obj = bestF;

    otherwise
        error('unknown method %s', method);
end

out.iters = it;
out.seconds = toc(t0);
end
