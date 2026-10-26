function s = rlgbka_features(f)
%RLGBKA_FEATURES  The 24-dimensional state the policy sees.
%
%   s = rlgbka_features(f)
%
%   f is a struct assembled by solve_rlgbka with these fields
%       .f          current penalised cost
%       .fBest      best feasible distance found so far
%       .scale      normaliser (the constructive solution's cost)
%       .stagnation iterations since the last improvement
%       .window     stagnation horizon used for normalisation
%       .nveh       routes in the current solution
%       .m          fleet limit
%       .capExcess  total capacity violation
%       .twExcess   total time-window violation
%       .nDemand    total demand, used to normalise capExcess
%       .horizon    time horizon, used to normalise twExcess
%       .eliteBest  best distance in the elite archive
%       .eliteDiv   mean pairwise distance between elite solutions
%       .opSucc     1x8 recent success counts
%       .opUse      1x8 recent use counts
%       .progress   fraction of the budget spent
%
% WHY THESE FEATURES
%   The policy has to answer one question: "should I refine locally, or escape,
%   or attack the fleet size?".  Local refinement pays off when the search is
%   making progress and violation is near zero; escaping pays off when the
%   improvement has stalled; fleet attack pays off when the vehicle count is
%   still above what capacity allows.  Every feature below is a direct
%   measurement of one of those conditions, and all are scaled to roughly [0,1]
%   so the network does not have to learn the units.

    sc = max(f.scale, 1e-9);

    s = zeros(1, 24);

    s(1) = f.f / sc;
    s(2) = f.fBest / sc;
    s(3) = min(1, f.stagnation / max(f.window, 1));
    s(4) = f.nveh / max(f.m, 1);
    s(5) = min(1, f.capExcess / max(f.nDemand * 0.1, 1e-9));
    s(6) = min(1, f.twExcess / max(f.horizon, 1e-9));
    s(7) = min(1, f.eliteBest / sc);
    s(8) = min(1, f.eliteDiv / sc);

    succ = f.opSucc(:)' ./ max(f.opUse(:)', 1);
    used = f.opUse(:)' / max(sum(f.opUse), 1);
    s(9:16)  = succ;
    s(17:24) = used;
end
