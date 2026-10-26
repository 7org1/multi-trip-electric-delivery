function test_core()
%TEST_CORE  Check the VRPTW core modules before building solvers on top of them.
%
% An insertion routine with an off-by-one in the time propagation still returns
% plausible costs, and every solver built on it would then be subtly wrong.
% These checks are cheap and catch that class of bug on the smallest instance.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    bdir = benchmark_dir();

    inst = read_vrptw_instance(fullfile(bdir, 'instances200', 'C1_2_1.TXT'));
    S = vrptw_model(inst);

    fprintf('instance %s : n=%d, Q=%g, m=%g\n', S.name, S.n, S.Q, S.m);
    fprintf('distance matrix %dx%d\n\n', S.N, S.N);

    % ---------------------------------------------------- 1. construction
    fprintf('=== 1. construction ===\n');
    tic; routes = vrptw_construct(S); tCon = toc;
    R = vrptw_eval(S, routes);
    fprintf('  vehicles %d, distance %.2f, feasible %d, %.2f s\n', ...
            R.nveh, R.cost, R.feasible, tCon);
    allc = [];
    for r = 1:numel(routes), allc = [allc, routes{r}]; end %#ok<AGROW>
    fprintf('  all %d customers served exactly once: %d\n', S.n, ...
            isequal(sort(allc), 2:S.N));
    assert(R.feasible, 'construction produced an infeasible solution');
    assert(isequal(sort(allc), 2:S.N), 'construction lost or duplicated customers');
    fprintf('  PASS\n\n');

    % --------------------------------------- 2. evaluation matches the hand sum
    fprintf('=== 2. route evaluation matches a hand computation ===\n');
    rt = routes{1};
    [ok, dist, tEnd, load] = vrptw_route_eval(S, rt);
    hand = S.D(1, rt(1));
    for k = 2:numel(rt)
        hand = hand + S.D(rt(k-1), rt(k));
    end
    hand = hand + S.D(rt(end), 1);
    fprintf('  route of %d customers: ok=%d dist=%g hand=%g tEnd=%g load=%g/%g\n', ...
            numel(rt), ok, dist, hand, tEnd, load, S.Q);
    assert(ok, 'a route from a feasible solution must be feasible');
    assert(abs(dist - hand) < 1e-9, 'distance mismatch');
    assert(load <= S.Q + 1e-9, 'load exceeds capacity');
    fprintf('  PASS\n\n');

    % ---------------------------------------- 3. infeasible routes are caught
    fprintf('=== 3. infeasibility detection ===\n');
    % overload: 20 customers in one vehicle
    big = 2:21;
    [okBig, distBig, ~, loadBig] = vrptw_route_eval(S, big);
    fprintf('  20 customers: load %g vs Q %g -> ok=%d, dist still complete (%g)\n', ...
            loadBig, S.Q, okBig, distBig);
    assert(~okBig, 'overloaded route must be flagged');

    % time window: visit the customer with the earliest due date last
    [~, late] = min(S.due(2:end));
    late = late + 1;
    others = setdiff(2:S.N, late);
    rt2 = [others(1:5), late];
    [okTW, dist2, ~] = vrptw_route_eval(S, rt2);
    fprintf('  early-due customer placed last -> ok=%d\n', okTW);
    assert(~okTW, 'a violated due date must be flagged');

    % distance must be complete even for the infeasible route
    hand2 = S.D(1, rt2(1));
    for k = 2:numel(rt2), hand2 = hand2 + S.D(rt2(k-1), rt2(k)); end
    hand2 = hand2 + S.D(rt2(end), 1);
    assert(abs(dist2 - hand2) < 1e-9, 'distance of an infeasible route must still be complete');
    fprintf('  PASS (distance complete even when infeasible)\n\n');

    % --------------------------------------------------- 4. insertion
    fprintf('=== 4. insertion ===\n');
    [r, pos, delta, found] = vrptw_insert_best(S, {rt(1:3)}, rt(4), true);
    fprintf('  insert customer %d: route %d pos %d delta %g found %d\n', ...
            rt(4)-1, r, pos, delta, found);
    assert(found, 'insertion into a feasible route should succeed');
    % verify the insertion really is feasible
    newRoutes = {rt(1:3)};
    if r == 1
        newRoutes{1} = [rt(1:min(pos-1,3)), rt(4), rt(pos:3)];
    else
        newRoutes{2} = rt(4);
    end
    okNew = vrptw_route_eval(S, newRoutes{1});
    assert(okNew, 'the returned insertion must be feasible');
    fprintf('  PASS\n\n');

    % --------------------------------------------------- 5. ALNS smoke test
    fprintf('=== 5. ALNS smoke test ===\n');
    opts = struct('maxIter', 2000, 'seed', 1, 'verbose', false);
    tic; [best, out] = solve_alns(S, opts); tAl = toc;
    fprintf('  vehicles %d, distance %.2f, feasible %d, %.1f s\n', ...
            out.nveh, out.cost, out.feasible, tAl);
    fprintf('  construction distance %.2f -> ALNS %.2f  (%.1f%%)\n', ...
            R.cost, out.cost, 100 * (R.cost - out.cost) / R.cost);
    fprintf('  curve: %s\n', mat2str(round(out.curve'), 6));
    assert(out.feasible, 'ALNS returned an infeasible solution');
    fprintf('  PASS\n');
end
