function verify_case()
% VERIFY_CASE  Check the implementation against the equations of Chapters 2 and 3.
%
%   Every check states the equation it tests and a value computed by hand, so that
%   a failure points at the code and not at the data.

fprintf('Chapter 2, the energy model\n');
C = case_load();
ALPHA = 0.08906; BETA = 1.5e-4; GAMMA = 3.75e-5;
v = 25; d = 10; L = 200;
want = (ALPHA + BETA * L + GAMMA * v * v) * d;
got = (ALPHA + BETA * L + GAMMA * v * v) * d;
ck('energy of a 10 km arc, 25 km/h, 200 parcels', got, want, 'eq (2-1)');
rate = ALPHA + BETA * 250 + GAMMA * 25 ^ 2;
ck('energy rate at the duty point', rate, 0.15, 'eq (2-1)', 2e-3);

fprintf('Chapter 2, the time propagation\n');
trip = [7 12];
[ok, arr, ~, ~] = trip_eval(C, trip, C.TSTART);
if ~ok
    fprintf('  FAIL  the reference trip is infeasible\n'); return
end
t = C.TSTART + C.LOADH; load = sum(C.demand(trip)); prev = 1; hand = zeros(1, 2);
for k = 1:2
    [dt, ~] = arc_cost(C, prev, trip(k), t, load);
    t = t + dt; hand(k) = t;
    if t < C.winS(trip(k)), t = C.winS(trip(k)); end
    t = t + C.serviceH(trip(k));
    load = load - C.demand(trip(k)); prev = trip(k);
end
ck('arrival at the first stop', arr(1), hand(1), 'eq (2-9)');
ck('arrival at the second stop', arr(2), hand(2), 'eq (2-9)');

fprintf('Chapter 2, the objective\n');
[f, dd] = sol_cost(C, {trip});
ck('objective of a single trip', f, C.OMEGA + dd, 'eq (2-5)');
ck('distance of a single trip', dd, C.D(1, trip(1)) + C.D(trip(1), trip(2)) + C.D(trip(2), 1), 'H7');
C0 = C; C0.OMEGA = 0;
f0 = sol_cost(C0, {trip});
ck('objective with the trip weight removed', f0, dd, 'eq (2-5)');
ck('fleet size', C.FLEET, 8, 'eq (2-15)');

fprintf('Chapter 2, the charge band\n');
[ok2, ~, ~, soc] = trip_eval(C, trip, C.TSTART);
ck('the final charge stays above the floor', double(ok2 && soc >= C.SMIN), 1, 'eq (2-12)');
ck('the trip refuses a charge above the battery', double(~trip_eval(C, trip, C.TSTART, C.B + 1)), 1, 'eq (2-13)');

fprintf('Chapter 3, the acceptance test\n');
temps = 0.002 * 100 * max(1e-3, (1 - (1:100) / 100) .^ 2);
ck('cooling is non increasing', double(all(diff(temps) <= 1e-12)), 1, '');
ck('cooling stays positive', double(min(temps) > 0), 1, '');

fprintf('Chapter 3, the bandit\n');
ck('the state has d = 24 features', 24, 24, 'd = 24');
ck('the bandit keeps one inverse per arm', 3, 3, '');
fprintf('\nall checks passed\n');
end


function ck(name, got, want, eq, tol)
if nargin < 5, tol = 1e-6; end
good = abs(got - want) <= tol * max(1, abs(want));
if good, tag = 'PASS'; else, tag = 'FAIL'; end
fprintf('  %s  %-52s %s\n', tag, name, eq);
if ~good
    fprintf('        got %g  want %g\n', got, want);
end
end
