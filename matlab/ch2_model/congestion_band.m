function b = congestion_band(C, hour)
% CONGESTION_BAND  Which congestion regime an hour belongs to.
%
%   1  light     s(t) <= 0.35   the early and late shoulders of the day
%   2  moderate  0.35 < s < 0.9 the long stretch either side of the peaks
%   3  heavy     s(t) >= 0.9    the morning and the evening peak
%
%   Grouping by congestion rather than by clock time puts the shoulders together and
%   keeps the two peaks apart, which is what the operator policy should react to.

s = shape_of_day(hour);
if s <= 0.35
    b = 1;
elseif s >= 0.90
    b = 3;
else
    b = 2;
end
end


function s = shape_of_day(h)
S = [0 6 0.00; 6 7 0.25; 7 9 1.00; 9 11 0.55; 11 13 0.45;
     13 17 0.50; 17 19 1.05; 19 22 0.35; 22 24 0.00];
h = mod(h, 24);
s = 0;
for i = 1:size(S, 1)
    if h >= S(i, 1) && h < S(i, 2)
        s = S(i, 3);
        return
    end
end
end
