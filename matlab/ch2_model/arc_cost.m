function [dt, e] = arc_cost(C, i, j, hour, load)
% ARC_COST  Travel time in hours and energy in kWh on arc (i,j), eq (2-1) and (2-2).
%
%   dt = d / (limit * mu) and e = (alpha + beta*load + gamma*v^2) * d,
%   with v the mean speed of the arc, capped at VMAX.
ALPHA = 0.0606;  BETA = 1.5e-4;  GAMMA = 2.933e-5;  DELTA = 0.840;  VMAX = 35.0;
d = C.D(i, j);
if d <= 0
    dt = 0; e = 0; return
end
b = speed_band(C, hour);
dt = C.Tall(b, i, j);
v = d / dt;
if v > VMAX
    v = VMAX;
end
e = (ALPHA + BETA * load + GAMMA * v * v + DELTA / max(v, 1.0)) * d;
end
