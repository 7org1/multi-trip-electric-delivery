function [t, soc] = soc_trace(C, tripList)
% SOC_TRACE  Charge of one vehicle over its day, on the clock of route_eval.
%
%   The time axis is the departure and return of each trip exactly as route_eval
%   reports them, so the trace is consistent with the Gantt view of the same solution.
%   The charge at a trip boundary is the charge before the trip less the energy its
%   arcs draw, with the load falling as parcels are delivered.

[ok, ~, ~, ~, ~, dep, ret] = route_eval(C, tripList, C.TSTART, C.B);
t = []; soc = [];
if ~ok, return, end
dep = dep(:)'; ret = ret(:)';
k = min(numel(dep), numel(ret));
if k == 0, return, end

E = zeros(1, k);
for j = 1:k
    trip = tripList{j};
    load = 0;
    for q = 1:numel(trip), load = load + C.demand(trip(q)); end
    clock = dep(j);
    prev = 1;
    for q = 1:numel(trip)
        [~, e] = arc_cost(C, prev, trip(q), clock, load);
        E(j) = E(j) + e;
        load = max(0, load - C.demand(trip(q)));
        clock = clock + C.Tall(speed_band(C, clock), prev, trip(q));
        prev = trip(q);
    end
    [~, e] = arc_cost(C, prev, 1, clock, load);
    E(j) = E(j) + e;
end

s = C.B;
for j = 1:k
    t(end+1) = dep(j);    soc(end+1) = s;      %#ok<AGROW>
    s = s - E(j);
    t(end+1) = ret(j);    soc(end+1) = s;      %#ok<AGROW>
    if j < k
        need = max(0, min(C.B - s, C.SMIN + E(j+1) - s));
        if need > 0
            s = s + need;
            t(end+1) = dep(j+1); soc(end+1) = s; %#ok<AGROW>
        end
    end
end
end
