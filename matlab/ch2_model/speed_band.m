function b = speed_band(C, hour)
% SPEED_BAND  Index of the speed band that contains the given hour.
h = mod(hour, 24);
b = 1;
for i = 1:size(C.BANDS, 1)
    if h >= C.BANDS(i, 1) && h < C.BANDS(i, 2)
        b = i;
        return
    end
end
end
