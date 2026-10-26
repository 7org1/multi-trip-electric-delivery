function d = trip_dist(C, trip)
% TRIP_DIST  Length of one trip, eq (2-8) with the depot at both ends.
if isempty(trip), d = 0; return, end
seq = [1, trip(:)', 1];
d = 0;
for k = 1:numel(seq)-1
    d = d + C.D(seq(k), seq(k+1));
end
end
