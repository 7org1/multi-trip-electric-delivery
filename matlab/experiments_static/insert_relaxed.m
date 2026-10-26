function [trips, unplaced] = insert_relaxed(C, trips, custs)
% INSERT_RELAXED  Greedy repair that gives up on a customer it cannot place.
%
%   A wave can only carry what the free vehicles can take, so a customer that fits
%   nowhere is left for the next wave rather than failing the whole repair.  The
%   caller charges for the unserved demand in the objective, which keeps the search
%   from dropping customers it could have served.

unplaced = [];
for q = 1:numel(custs)
    c = custs(q);
    bestK = 0; bestP = []; bestD = inf;
    for k = 1:numel(trips)
        [p, dd] = best_insert(C, trips{k}, c);
        if isempty(p), continue, end
        if dd < bestD, bestD = dd; bestK = k; bestP = p; end
    end
    if bestK == 0
        if numel(trips) < C.CAPTRIPS && trip_eval(C, c, C.NOW)
            trips{end+1} = c; %#ok<AGROW>
        else
            unplaced(end+1) = c; %#ok<AGROW>
        end
    else
        t = trips{bestK}(:).';
        trips{bestK} = [t(1:bestP-1), c, t(bestP:end)];
    end
end
end
