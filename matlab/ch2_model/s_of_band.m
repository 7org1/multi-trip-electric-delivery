function s = s_of_band(k)
% S_OF_BAND  Congestion level s(t) that belongs to speed band k.
%
%   The shape of the day, from Table 2 of the paper.  Band k covers the k-th row of
%   C.BANDS, which is the interval [0 6), [6 7), [7 9), ... of the day.

S = [0.00; 0.25; 1.00; 0.55; 0.45; 0.50; 1.05; 0.35; 0.00];
s = S(min(max(k, 1), numel(S)));
end
