function diag_ruin()
%DIAG_RUIN  Can large-scale ruin-and-recreate reach the best-known fleet size?
%
% Single-customer moves cannot empty a route unless that route holds one
% customer, so no amount of relocate/exchange/2-opt* will take 21 routes down to
% 20.  The question this answers is whether removing a large share of customers
% and reinserting them into the remaining routes does consolidate, because that
% decides which operator family the baselines actually need.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    inst = read_vrptw_instance(fullfile(benchmark_dir(), 'instances200', 'C1_2_1.TXT'));
    S = vrptw_model(inst);

    base = vrptw_construct(S);
    Rb = vrptw_eval(S, base);
    fprintf('start: %d routes, dist %.2f\n\n', Rb.nveh, Rb.cost);

    % target: 20 routes.  Every route is a slot we may keep or empty.
    S20 = S; S20.m = 20;

    fprintf('%-8s %6s %10s %10s %s\n', 'q(%)', 'trials', 'succeeded', 'bestVeh', 'note');
    fprintf('%s\n', repmat('-', 1, 56));

    for frac = [0.10 0.20 0.30 0.40 0.50]
        q = round(frac * S.n);
        nSucc = 0; bestVeh = inf; tries = 30;
        rng(7);
        for t = 1:tries
            % remove q random customers, then reinsert with the fleet capped
            rt = base;
            allC = zeros(0,1);
            for r = 1:numel(rt), allC = [allC; rt{r}(:)]; end %#ok<AGROW>
            rem = allC(randperm(numel(allC), q));
            for i = 1:numel(rem)
                c = rem(i);
                for r = 1:numel(rt)
                    pos = find(rt{r} == c, 1);
                    if ~isempty(pos), rt{r}(pos) = []; break; end
                end
            end
            % drop empty slots so reinsertion must use the survivors
            keep = ~cellfun(@isempty, rt);
            rt = rt(keep);

            pend = rem(:)';
            okAll = true;
            while ~isempty(pend)
                bestC = 0; bestD = inf; bestR = 0; bestP = 0;
                for i = 1:numel(pend)
                    [rr, pp, dd, found] = vrptw_insert_best(S20, rt, pend(i), false);
                    if found && dd < bestD
                        bestD = dd; bestC = pend(i); bestR = rr; bestP = pp;
                    end
                end
                if bestC == 0
                    okAll = false; break;
                end
                rtc = rt{bestR};
                rt{bestR} = [rtc(1:bestP-1), bestC, rtc(bestP:end)];
                pend(pend == bestC) = [];
            end
            if okAll
                R = vrptw_eval(S20, rt);
                if R.feasible
                    nSucc = nSucc + 1;
                    bestVeh = min(bestVeh, R.nveh);
                end
            end
        end
        note = '';
        if nSucc > 0, note = 'consolidation possible'; end
        fprintf('%-8d %6d %10d %10s %s\n', round(100*frac), tries, nSucc, ...
                num2str(bestVeh), note);
    end

    fprintf('\n=== interpretation ===\n');
    fprintf('If even 50%% removal cannot reinsert everything into 20 routes,\n');
    fprintf('the instance needs a different global strategy, not a better local move.\n');
end
