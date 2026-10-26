function out = cblns_v3(C, budget, seed, alphaMode, armSet, cooling, guards)
% CBLNS_V3  The contextual bandit large neighbourhood search of Chapter 3.
%
%   out = cblns_v3(C, budget, seed, alphaMode, armSet)
%
%   alphaMode  'decay'  alpha_t / sqrt(t), the default
%              'v3'     alpha_t as written, kept for the comparison
%              'const'  alpha_t = 1
%   armSet     'ch3'    the three operators of Chapter 3
%              'full'   with the whole-trip neighbourhood
%
%   The destroy operator is chosen by a linear contextual bandit with the
%   standardised score
%
%       p_a = theta' s / vbar + alpha_t * sqrt(s' A^-1 s) / bbar,
%       alpha_t = sqrt(d * ln(1 + t / delta)),
%
%   with A_a initialised to the identity and updated by Sherman-Morrison.  vbar and
%   bbar are the running scales of the two terms.
%
%   Two safeguards are added.  A 5% exploration floor keeps a decaying bonus from
%   locking on one arm forever.  The current solution is pulled back to the best
%   once it has drifted more than 1% above it, which is the usual guard against a
%   random walk.

if nargin < 2, budget = 60; end
if nargin < 3, seed = 1; end
if nargin < 4, alphaMode = 'decay'; end
if nargin < 5, armSet = 'full'; end
if nargin < 6, cooling = 'dyn'; end
if nargin < 7, guards = true; end
rng(seed, 'twister');

d = 24;
delta = 0.05;
if strcmpi(armSet, 'ch3')
    nArms = 3;
else
    nArms = 4;
end
arms = {'sector', 'worst', 'random', 'trip'};
arms = arms(1:nArms);
Ainv = repmat({eye(d)}, 1, nArms);
bvec = repmat({zeros(d, 1)}, 1, nArms);
vbar = 1; bbar = 1; nUpd = 0;

% initial solution, farthest point first
order = 2:C.n;
[~, ord] = sort(C.D(1, order), 'descend');
trips = {};
[trips, ok] = insert_all(C, trips, order(ord));
if ~ok
    error('the initial solution is infeasible');
end
[curF, ~] = sol_cost(C, trips);
best = trips; bestF = curF; f0 = curF;

t0 = tic; it = 0; tRef = 0.01; sinceBest = 0; nPick = zeros(1, nArms);
cong = fleet_congestion(C, trips); pickExp = zeros(3, 200000); pickArm = zeros(1, 200000);
while toc(t0) < budget
    it = it + 1;
    el = toc(t0);
    if mod(it, 20) == 1, cong = fleet_congestion(C, trips); end
    s = bandit_state(C, trips, curF, bestF, f0, it, el, budget, cong);

    switch alphaMode
        case 'const'
            at = 1.0;
        case 'v3'
            at = sqrt(d * log(1 + it / delta));
        case 'shrink'
            at = sqrt(d * log(1 + it / delta)) / (1 + it / 200);
        otherwise
            at = sqrt(d * log(1 + it / delta)) / sqrt(max(1, it));
    end

    score = zeros(1, nArms);
    for a = 1:nArms
        th = Ainv{a} * bvec{a};
        mu = th' * s;
        sd = sqrt(max(1e-12, s' * Ainv{a} * s));
        if nUpd >= 5
            score(a) = mu / vbar + at * sd / bbar;
        else
            score(a) = mu + at * sd;
        end
    end
    [~, ai] = max(score);
    if guards && rand < 0.05
        ai = randi(nArms);              % exploration floor
    end
    nPick(ai) = nPick(ai) + 1;
    if it <= size(pickExp, 2), pickExp(:, it) = cong(1:3); pickArm(it) = ai; end

    q = 6 + floor(rand * 9);
    [removed, partial] = destroy(C, trips, arms{ai}, q);
    if isempty(removed), continue, end
    cand = partial;
    [cand, ok] = insert_all(C, cand, removed);
    if ~ok, continue, end
    [f, ~] = sol_cost(C, cand);

    % geometric cooling, feasibility only.  The horizon is re-estimated from the
    % observed iteration rate, otherwise the temperature reaches its floor long
    % before the budget is spent and the search becomes a greedy descent.
    if strcmpi(cooling, 'fix')
        Kest = budget * 40;
    elseif el > 0.5
        Kest = max(200, it / max(0.02, el / budget));
    else
        Kest = budget * 40;
    end
    T = 0.002 * f0 * max(1e-3, (1 - it / Kest) ^ 2);

    sinceBest = sinceBest + 1;
    if guards && sinceBest > 400 && curF > bestF * 1.01
        trips = best; curF = bestF; sinceBest = 0;    % drift guard
    end

    improved = f < curF - 1e-9;
    accept = improved || rand < exp(-(f - curF) / max(T, 1e-9));
    if accept
        r = max(0, (curF - f) / f0) * (tRef / max(tRef, el / max(1, it)));
        r = min(1, r);
        [Ainv{ai}, bvec{ai}] = sherman(Ainv{ai}, bvec{ai}, s, r);
        [vbar, bbar, nUpd] = rescale(Ainv{ai}, bvec{ai}, s, vbar, bbar, nUpd);
        trips = cand; curF = f;
        if f < bestF - 1e-9
            best = cand; bestF = f; sinceBest = 0;
        end
    end
end

out.trips = best;
out.obj = bestF;
out.iters = it;
out.seconds = toc(t0);
out.name = 'CBLNS';
out.share = nPick / max(1, sum(nPick));
% Arm mix in the high and low states of each period.  This is the evidence that the
% operator choice depends on the context, and which period drives it.
n = min(it, size(pickExp, 2));
ex = pickExp(:, 1:n); ar = pickArm(1:n);
lab = {'morning', 'daytime', 'evening'};
out.periods = lab;
out.pLow = zeros(1, 3);  out.pHigh = zeros(1, 3);
out.shareLow = zeros(3, nArms);  out.shareHigh = zeros(3, nArms);
for j = 1:3
    q = prctile(ex(j, :), [33 67]);
    lo = ex(j, :) <= q(1);  hi = ex(j, :) >= q(2);
    out.pLow(j) = mean(ex(j, lo));  out.pHigh(j) = mean(ex(j, hi));
    for a = 1:nArms
        out.shareLow(j, a) = mean(ar(lo) == a);
        out.shareHigh(j, a) = mean(ar(hi) == a);
    end
end
end