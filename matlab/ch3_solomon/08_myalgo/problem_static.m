function P = problem_static(S)
%PROBLEM_STATIC  Adapter that exposes a VRPTW instance to the solver.
%
%   P = problem_static(S)
%
%   The solver NEVER touches the instance struct directly.  Everything it needs
%   goes through the handful of fields and function handles below.  That single
%   rule is what lets the same search code run on the Solomon / Gehring-
%   Homberger benchmarks and, later, on the time-dependent Nanjing road network:
%   the time-dependent case only has to supply another adapter with the same
%   signatures, and solve_rlgbka.m is not touched.
%
%   FIELDS
%     P.n P.N P.m P.Q P.depot      problem size, fleet, capacity, depot index
%     P.demand P.ready P.due P.service   [N x 1] node data
%     P.timeDependent              false here; the TD adapter sets it true
%
%   HANDLES (the whole interface the solver is allowed to use)
%     P.eval(routes, lam)            -> [f, viol, R]
%     P.insert(routes, j, allowNew)  -> [r, p, delta, found, perRoute]
%     P.stats(route)                 -> st.dist st.capExcess st.twExcess
%     P.construct()                  -> initial feasible routes
%     P.evalReport(routes)           -> R.cost R.nveh R.feasible (authority)
%
% WHY AN ADAPTER RATHER THAN PASSING S AROUND
%   A time-dependent problem cannot answer "what is the cost of this route"
%   without also being told when the vehicle departs, and it derives the path
%   between consecutive customers from a shortest-path query rather than from a
%   matrix lookup.  Hiding that behind P.stats / P.eval is what keeps the
%   operator library and the policy unaware of the difference.

    P = struct();
    P.name          = S.name;
    P.n             = S.n;
    P.N             = S.N;
    P.m             = S.m;
    P.Q             = S.Q;
    P.depot         = S.depot;
    P.demand        = S.demand;
    P.ready         = S.ready;
    P.due           = S.due;
    P.service       = S.service;
    P.timeDependent = false;

    P.eval       = @(routes, lam) vrptw_penalized_cost(S, routes, lam);
    P.insert     = @(routes, j, allowNew) vrptw_insert_best(S, routes, j, allowNew);
    P.stats      = @(route) vrptw_route_stats(S, route);
    P.construct  = @() vrptw_construct(S);
    P.evalReport = @(routes) vrptw_eval(S, routes);

    P.S = S;   % kept only for diagnostics; the solver must not use it
end
