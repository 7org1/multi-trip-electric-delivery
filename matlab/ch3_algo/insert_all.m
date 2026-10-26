function [trips, ok] = insert_all(C, trips, custs)
% INSERT_ALL  Greedy repair, the same in every method.
%
%   Each customer goes to the position that adds the least distance among all
%   feasible positions of all trips.  A customer that fits nowhere opens a new
%   trip, which is the only way the number of trips can grow.
ok = true;
for q = 1:numel(custs)
    c = custs(q);
    bestK = 0; bestP = []; bestD = inf;
    for k = 1:numel(trips)
        [p, dd] = best_insert(C, trips{k}, c);
        if isempty(p), continue, end
        if dd < bestD
            bestD = dd; bestK = k; bestP = p;
        end
    end
    if bestK == 0
        % a new trip is only opened while the fleet has a vehicle left
        if numel(trips) < C.CAPTRIPS && trip_eval(C, c, C.NOW)
            trips{end+1} = c; %#ok<AGROW>
        else
            ok = false; return
        end
    else
        t = trips{bestK}(:).';          % every trip is kept as a row
        trips{bestK} = [t(1:bestP-1), c, t(bestP:end)];
    end
end
end
