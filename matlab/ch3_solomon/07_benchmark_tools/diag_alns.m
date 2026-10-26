function diag_alns(C1_2_1_focus)
%DIAG_ALNS  Two questions before tuning anything.
%
%   1. Is the best-known vehicle count even reachable by the operators?  The
%      construction gives 21 routes; the best known is 20.  If removing one
%      route and re-inserting its customers with new routes forbidden never
%      succeeds, then no amount of iteration will find 20, and the penalty or
%      the repair policy is wrong rather than the budget.
%
%   2. Where does the time go?  Optimising the wrong part of the loop is the
%      usual reason a MATLAB ALNS feels unusably slow.

    if nargin < 1, C1_2_1_focus = true; end %#ok<NASGU>

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    inst = read_vrptw_instance(fullfile(benchmark_dir(), 'instances200', 'C1_2_1.TXT'));
    S = vrptw_model(inst);

    routes = vrptw_construct(S);
    R0 = vrptw_eval(S, routes);
    fprintf('construction: %d vehicles, distance %.2f\n\n', R0.nveh, R0.cost);

    % ------------------------------------------------- 1. is 20 reachable?
    fprintf('=== 1. remove one whole route, re-insert with new routes FORBIDDEN ===\n');
    fprintf('%-8s %8s %10s %10s %s\n', 'removed', 'nCust', 'resultVeh', 'allPlaced', 'note');
    bestVeh = inf;
    for r = 1:numel(routes)
        if isempty(routes{r}), continue; end
        trial = routes;
        removed = trial{r};
        trial(r) = [];   % delete the SLOT, not just its contents
        placed = true;
        pend = removed;
        while ~isempty(pend)
            bestC = 0; bestD = inf; bestR = 0; bestP = 0;
            for i = 1:numel(pend)
                [rr, pp, dd, found] = vrptw_insert_best(S, trial, pend(i), false);
                if found && dd < bestD
                    bestD = dd; bestC = pend(i); bestR = rr; bestP = pp;
                end
            end
            if bestC == 0
                placed = false;
                break;
            end
            if bestR > numel(trial)
                trial{end+1} = bestC;
            else
                rt = trial{bestR};
                trial{bestR} = [rt(1:bestP-1), bestC, rt(bestP:end)];
            end
            pend(pend == bestC) = [];
        end
        Rv = vrptw_eval(S, trial);
        note = '';
        if placed && Rv.nveh < bestVeh, bestVeh = Rv.nveh; end
        if ~placed, note = 'could not place all'; end
        fprintf('%-8d %8d %10d %10d %s\n', r, numel(removed), Rv.nveh, placed, note);
    end
    fprintf('\nlowest vehicle count reachable by this move: %d\n', bestVeh);
    if bestVeh <= 20
        fprintf('=> 20 IS reachable; the search just needs to find and keep it.\n');
    else
        fprintf('=> 20 is NOT reachable with this move; the repair policy is the problem.\n');
    end

    % ------------------------------------------------------ 2. timing
    fprintf('\n=== 2. where the time goes (2000 iterations) ===\n');
    rng(1);
    q = 12;
    tD = 0; tR = 0; tE = 0; nIter = 300;
    cur = routes;
    for it = 1:nIter
        t0 = tic;
        [partial, removed] = destroyOnce(S, cur, q);
        tD = tD + toc(t0);

        t0 = tic;
        cand = repairOnce(S, partial, removed);
        tR = tR + toc(t0);

        t0 = tic;
        Rc = vrptw_eval(S, cand);
        tE = tE + toc(t0);
        if rand < 0.3, cur = cand; end %#ok<NASGU>
    end
    fprintf('  destroy : %7.2f ms/iter\n', 1000 * tD / nIter);
    fprintf('  repair  : %7.2f ms/iter   <-- usually the bottleneck\n', 1000 * tR / nIter);
    fprintf('  evaluate: %7.2f ms/iter\n', 1000 * tE / nIter);
    fprintf('  total   : %7.2f ms/iter\n', 1000 * (tD + tR + tE) / nIter);
end


function [routes, removed] = destroyOnce(S, routes, q)
    allC = zeros(0,1);
    for r = 1:numel(routes), allC = [allC; routes{r}(:)]; end %#ok<AGROW>
    allC = allC(:)';
    q = min(q, numel(allC));
    removed = allC(randperm(numel(allC), q));
    for i = 1:numel(removed)
        c = removed(i);
        for r = 1:numel(routes)
            pos = find(routes{r} == c, 1);
            if ~isempty(pos)
                routes{r}(pos) = [];
                break;
            end
        end
    end
end

function routes = repairOnce(S, routes, removed)
    pend = removed(:)';
    while ~isempty(pend)
        bestC = 0; bestD = inf; bestR = 0; bestP = 0;
        for i = 1:numel(pend)
            [rr, pp, dd, found] = vrptw_insert_best(S, routes, pend(i), false);
            if found && dd < bestD
                bestD = dd; bestC = pend(i); bestR = rr; bestP = pp;
            end
        end
        if bestC == 0
            bestC = pend(1);
            [bestR, bestP] = deal(numel(routes) + 1, 1);
        end
        if bestR > numel(routes)
            routes{end+1} = bestC;
        else
            rt = routes{bestR};
            routes{bestR} = [rt(1:bestP-1), bestC, rt(bestP:end)];
        end
        pend(pend == bestC) = [];
    end
end
