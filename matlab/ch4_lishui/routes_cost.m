function [f, d, ok, trips, served] = routes_cost(C, routes)
% ROUTES_COST  Objective of a whole day: eq (2-5), the trip weight plus the distance.
%
%   A route that is infeasible makes the whole plan infeasible, which is returned as
%   ok = false and a large cost so that the search never prefers it.

f = Inf; d = Inf; ok = false; trips = 0; served = 0;
dd = 0; nt = 0; sv = 0;
for v = 1:numel(routes)
    [okr, dv, sv1, ~, ~, ~, ~] = route_eval(C, routes{v}, C.TSTART, C.B);
    if ~okr, return, end
    dd = dd + dv; nt = nt + numel(routes{v}); sv = sv + sv1;
end
d = dd; trips = nt; served = sv;
f = C.OMEGA * nt + dd;
ok = true;
end
