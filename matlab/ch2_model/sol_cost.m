function [f, d] = sol_cost(C, trips)
% SOL_COST  Objective of eq (2-5), the trip weight plus the total distance.
d = 0;
for k = 1:numel(trips)
    d = d + trip_dist(C, trips{k});
end
f = C.OMEGA * numel(trips) + d;
end
