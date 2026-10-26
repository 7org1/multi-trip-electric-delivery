function [p, dInc] = best_insert(C, trip, c)
% BEST_INSERT  Cheapest feasible insertion position of customer c in the trip.
%
%   Returns an empty p when no position keeps the trip feasible under capacity,
%   the time windows and the charge band.
p = []; dInc = inf;
if isempty(trip)
    if trip_eval(C, c, C.NOW)
        p = 1; dInc = trip_dist(C, c);
    end
    return
end
base = trip_dist(C, trip);
n = numel(trip);
for k = 0:n
    cand = [trip(1:k), c, trip(k+1:end)];
    [ok, ~, ~, ~] = trip_eval(C, cand, C.NOW);
    if ~ok, continue, end
    dd = trip_dist(C, cand) - base;
    if dd < dInc
        dInc = dd; p = k + 1;
    end
end
end
