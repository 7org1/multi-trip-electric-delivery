function s = slack_c(C, c, t)
% SLACK_C  Hours left before customer c can no longer be served from the depot.
%
%   A dedicated round trip is assumed: out along the shortest path under the speed of
%   the hour of departure, back under the speed of the hour of return.  The last
%   arrival allowed for c is the earlier of its window closing and the latest hour
%   that still leaves time for the return leg before the day ends.
%
%   A negative slack means the customer can no longer be reached at all, so leaving
%   it behind costs nothing that a decision could avoid.

b1 = speed_band(C, t);
tout = C.Tall(b1, 1, c);
b2 = speed_band(C, t + tout);
tback = C.Tall(b2, c, 1);
latestArrive = min(C.winE(c), C.TEND - tback);
s = latestArrive - tout - t;
end
