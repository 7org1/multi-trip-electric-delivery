function diag_savings()
%DIAG_SAVINGS  Does a Clarke-Wright style merging construction reach the
%best-known fleet size where sequential insertion does not?
%
% Sequential insertion grew 21 routes for c1_2_1 while the best known uses 20.
% That is exactly the symptom Clarke-Wright was designed for: start from one
% route per customer and merge, because merging directly targets the number of
% routes, whereas insertion only targets the distance of the next customer.
%
% Feasibility check after a merge is a full route evaluation, which is fine
% here: this is a construction, evaluated a few thousand times at most.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    inst = read_vrptw_instance(fullfile(benchmark_dir(), 'instances200', 'C1_2_1.TXT'));
    S = vrptw_model(inst);

    routes = num2cell(2:S.N);          % one route per customer
    nR = numel(routes);
    fprintf('start: %d routes (one per customer)\n', nR);

    improved = true; iter = 0;
    while improved
        improved = false; iter = iter + 1;
        bestSav = -inf; bi = 0; bj = 0; bmode = 0;

        for i = 1:numel(routes)
            if isempty(routes{i}), continue; end
            a = routes{i};
            for j = i+1:numel(routes)
                if isempty(routes{j}), continue; end
                b = routes{j};
                % four ways to join two routes end to end
                cand = { [a, b], [a, fliplr(b)], [fliplr(a), b], [fliplr(a), fliplr(b)] };
                for m = 1:4
                    c = cand{m};
                    sav = routeCost(S, a) + routeCost(S, b) - routeCost(S, c);
                    if sav > bestSav + 1e-9
                        % feasibility of the joined route
                        if isFeasible(S, c)
                            bestSav = sav; bi = i; bj = j; bmode = m;
                        end
                    end
                end
            end
        end

        if bi > 0
            a = routes{bi}; b = routes{bj};
            cand = { [a, b], [a, fliplr(b)], [fliplr(a), b], [fliplr(a), fliplr(b)] };
            routes{bi} = cand{bmode};
            routes{bj} = [];
            improved = true;
        end
    end

    keep = ~cellfun(@isempty, routes);
    routes = routes(keep);
    R = vrptw_eval(S, routes);
    fprintf('after merging: %d routes, dist %.2f, feasible %d, %d passes\n', ...
            R.nveh, R.cost, R.feasible, iter);
    fprintf('BKS: 20 routes, 2704.57\n');
end

function c = routeCost(S, rt)
    if isempty(rt), c = 0; return; end
    c = vrptw_route_stats(S, rt).dist;
end

function ok = isFeasible(S, rt)
    ok = vrptw_route_stats(S, rt).feasible;
end
