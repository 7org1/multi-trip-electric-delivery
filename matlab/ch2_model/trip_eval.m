function [ok, arr, ret, socEnd] = trip_eval(C, trip, depart, soc0)
% TRIP_EVAL  Walk one trip and check capacity, windows and the state of charge.
%
%   [ok, arr, ret, socEnd] = trip_eval(C, trip, depart, soc0)
%
%   The speed band is re-evaluated at every arc from the current hour, so a trip
%   that starts in the daytime and runs into the peak pays the peak on its later
%   arcs.  Arriving before a window opens means waiting, eq (2-10).  The charge
%   carried in by soc0 is subtracted arc by arc and may not fall below SMIN,
%   eq (2-12) and (2-13).

if nargin < 3 || isempty(depart), depart = C.TSTART; end
if nargin < 4 || isempty(soc0),   soc0 = C.B;        end

ok = false; arr = []; ret = []; socEnd = [];
if isempty(trip), return, end

load = sum(C.demand(trip));
if load > C.Q, return, end                    % eq (2-7)
if soc0 > C.B + 1e-9, return, end             % eq (2-13)

t = depart + C.LOADH;
prev = 1;
soc = soc0;
arr = zeros(1, numel(trip));
for k = 1:numel(trip)
    c = trip(k);
    [dt, e] = arc_cost(C, prev, c, t, load);
    t = t + dt;
    soc = soc - e;
    if soc < C.SMIN - 1e-9, return, end       % eq (2-12)
    if t > C.winE(c) + 1e-9, return, end      % eq (2-10)
    arr(k) = t;
    if t < C.winS(c), t = C.winS(c); end
    t = t + C.serviceH(c);
    load = load - C.demand(c);
    prev = c;
end
[dt, e] = arc_cost(C, prev, 1, t, 0);
t = t + dt;
soc = soc - e;
if soc < C.SMIN - 1e-9, return, end
if t > C.TEND + 1e-9, return, end

ret = t;
socEnd = soc;
ok = true;
end
