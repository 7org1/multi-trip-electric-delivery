function [routes, ok, f, d, logmsg] = build_routes(C, F, order)
% BUILD_ROUTES  Greedy construction of a whole day for F vehicles.
%
%   The construction works in rounds.  In each round every vehicle that can still
%   leave opens one trip and fills it, then the next round starts.  Filling one
%   vehicle to the end of its day before touching the next leaves the last vehicles
%   with the customers nobody else could take, which is how a plan that should fit
%   ends up a few customers short.
%
%   Within a trip, customers are taken in the order given, which the caller sets by
%   urgency, and each is placed where it adds the least distance.

remaining = order(:)';
routes = repmat({cell(1, 0)}, 1, F);
blocked = false(1, F);
logmsg = [];

for round = 1:50
    progressed = false;
    for v = 1:F
        if blocked(v) || isempty(remaining), continue, end
        seed = remaining(1);
        R2 = routes{v};
        R2{end+1} = seed;
        [okr, ~, ~, ~, ~, ~, ~] = route_eval(C, R2, C.TSTART, C.B);
        if ~okr
            blocked(v) = true;
            continue
        end
        routes{v} = R2;
        remaining(1) = [];
        progressed = true;

        % fill this trip
        changed = true;
        while changed && ~isempty(remaining)
            changed = false;
            k = numel(routes{v});
            t = routes{v}{k};
            base = trip_dist(C, t);
            bestD = Inf; bestQ = 0; bestP = 0;
            for q = 1:numel(remaining)
                c = remaining(q);
                for p = 1:numel(t) + 1
                    cand2 = [t(1:p-1), c, t(p:end)];
                    R3 = routes{v}; R3{k} = cand2;
                    [okr, ~, ~, ~, ~, ~, ~] = route_eval(C, R3, C.TSTART, C.B);
                    if ~okr, continue, end
                    dd = trip_dist(C, cand2) - base;
                    if dd < bestD
                        bestD = dd; bestQ = q; bestP = p;
                    end
                end
            end
            if bestQ > 0
                routes{v}{k} = [t(1:bestP-1), remaining(bestQ), t(bestP:end)];
                remaining(bestQ) = [];
                changed = true;
            end
        end
    end
    logmsg(end+1) = numel(remaining); %#ok<AGROW>
    if isempty(remaining) || ~progressed, break, end
end

if ~isempty(remaining)
    ok = false; routes = {}; f = Inf; d = Inf; return
end
[f, d, ok] = routes_cost(C, routes);
end
