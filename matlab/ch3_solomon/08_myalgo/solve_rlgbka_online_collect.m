function [best, out] = solve_rlgbka_online_collect(P, opts, sampleEvery)
%SOLVE_RLGBKA_ONLINE_COLLECT  The online solver, also collecting a route pool.
%
%   Thin wrapper: the solver itself takes opts.samplePool, this only exists so the
%   experiment reads clearly.
    if nargin < 3 || isempty(sampleEvery), sampleEvery = 20; end
    opts.samplePool = sampleEvery;
    [best, out] = solve_rlgbka_online(P, opts);
end
