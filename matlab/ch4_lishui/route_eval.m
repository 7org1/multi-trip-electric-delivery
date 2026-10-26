function [ok, dist, served, endT, socEnd, dep, ret] = route_eval(C, route, t0, soc0)
% ROUTE_EVAL  Drive one vehicle's whole sequence of trips.
%
%   A route is a cell array of trips.  Consecutive trips are chained: the next one
%   may leave only after the previous has returned and the depot work is done, and
%   the depot work is the longer of loading and recharging.  A vehicle recharges only
%   what the next trip needs, because the model carries no energy price and charging
%   earlier would only consume hours that could be driven (the policy agreed for the
%   case).
%
%   The last return may not pass the end of the operating day; that check lives in
%   trip_eval, so a route that would run late fails here.

ok = false; dist = 0; served = 0; endT = t0; socEnd = soc0;
dep = zeros(1, numel(route)); ret = zeros(1, numel(route));
if isempty(route)
    ok = true; return
end

t = t0;
soc = soc0;
for k = 1:numel(route)
    trip = route{k};
    if isempty(trip), continue, end

    [okB, ~, ~, socFull] = trip_eval(C, trip, t, C.B);
    if ~okB, return, end
    need = C.B - socFull;
    if need + C.SMIN > C.B + 1e-9, return, end     % one trip cannot exceed the battery

    ch = 0;
    if soc - need < C.SMIN
        ch = (need + C.SMIN - soc) / C.PCH;        % only what the trip needs
        soc = need + C.SMIN;
    end
    d0 = t + max(C.LOADH, ch);

    [okT, ~, r, socNew] = trip_eval(C, trip, d0, soc);
    if ~okT, return, end

    dep(k) = d0; ret(k) = r;
    dist = dist + trip_dist(C, trip);
    served = served + sum(C.demand(trip));
    t = r;
    soc = socNew;
end

endT = t;
socEnd = soc;
ok = true;
end
