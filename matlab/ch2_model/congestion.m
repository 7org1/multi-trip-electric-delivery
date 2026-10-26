function [share, dom, mu] = congestion(C, trip, depart)
% CONGESTION  How a trip's driving time splits across the congestion regimes.
%
%   The trip is walked from the hour it actually leaves, so a trip that runs at ten in
%   the morning is attributed to the moderate regime and one that runs at six to the
%   light regime.  Without the departure the walk always started at the opening hour,
%   every trip looked alike, and the moderate regime never occurred at all.
%
%     share  fraction of the driving time in light / moderate / heavy
%     dom    the regime taking most of the driving time
%     mu     mean congestion level, weighted by the time spent on each arc

if nargin < 3 || isempty(depart)
    if isfield(C, 'NOW'), depart = C.NOW; else, depart = C.TSTART; end
end

t = depart;
prev = 1;
acc = zeros(1, 3);
total = 0;
wsum = 0;
for k = 1:numel(trip)
    c = trip(k);
    b = speed_band(C, t);
    dt = C.Tall(b, prev, c);
    t = t + dt;
    total = total + dt;
    wsum = wsum + dt * s_of_band(b);
    g = congestion_band(C, t);
    acc(g) = acc(g) + dt;
    prev = c;
end
b = speed_band(C, t);
dt = C.Tall(b, prev, 1);
total = total + dt;
wsum = wsum + dt * s_of_band(b);
g = congestion_band(C, t);
acc(g) = acc(g) + dt;

if total > 0
    share = acc / total;
    mu = wsum / total;
else
    share = [0 0 0];
    mu = 0;
end
[~, dom] = max(share);
if isempty(dom), dom = 1; end
end
