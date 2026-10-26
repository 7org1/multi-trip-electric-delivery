function [routes, out] = solve_day(C, F, method, budget, seed, useCong, onlyArm)
if nargin < 6 || isempty(useCong), useCong = true; end
if nargin < 7 || isempty(onlyArm), onlyArm = 0; end
% SOLVE_DAY  One call, one whole day, F vehicles.
%
%   The solution is F vehicle routes, each a sequence of trips, each a sequence of
%   customers.  A route is feasible when its trips can be chained inside the
%   operating day, respecting capacity, the service windows, the charge band and the
%   recharge that has to happen between two trips.
%
%   The destroy operator is chosen by one of three bandits, and the bandit is picked
%   by the congestion regime of the trips the destroyed customers came from.  A
%   policy learned in heavy congestion is therefore never applied to a trip that runs
%   in light traffic.
%
%   method  CBLNS / ALNS / VNS / Tabu / GA

rng(seed, 'twister');
d = 24; delta = 0.05; nArms = 3;
arms = {'sector', 'worst', 'random'};
pol = upper(method);

% one bandit, as in Chapter 3; the congestion regime enters through the state
Ainv = repmat({eye(d)}, 1, nArms);
bvec = repmat({zeros(d, 1)}, 1, nArms);
vbar = 1; bbar = 1; nUpd = 0;
nPick = zeros(3, nArms);
wgt = ones(1, nArms); wsc = zeros(1, nArms); wus = zeros(1, nArms);
tabuUntil = zeros(1, C.n);

% construction: the tightest customers go in first
order = 2:C.n;
sl = zeros(1, numel(order));
for i = 1:numel(order), sl(i) = slack_c(C, order(i), C.TSTART); end
[~, ord] = sort(sl, 'ascend');
[routes, ok, curF, ~] = build_routes(C, F, order(ord));
if ~ok
    routes = {}; out = struct('feasible', false, 'obj', Inf, 'trips', Inf, ...
        'distance', Inf, 'share', nPick, 'iters', 0, 'served', 0);
    return
end
best = routes; bestF = curF; f0 = max(1, curF);

% a genetic run keeps its own population
if strcmp(pol, 'GA')
    [best, bestF] = ga_loop(C, F, routes, curF, budget);
    routes = best;
    out = describe(C, routes, bestF, nPick, 0, true);
    return
end

t0 = tic; it = 0; sinceBest = 0;
if useCong, bandMix = band_mix(C, routes); else, bandMix = zeros(3,1); end
% tercile cut points of the mean congestion level over the trips of the construction,
% so that the three regimes hold about a third of the trips each
MU = [];
for vv = 1:numel(routes)
    [okv, ~, ~, ~, ~, dp, ~] = route_eval(C, routes{vv}, C.TSTART, C.B);
    if ~okv, continue, end
    for kk = 1:min(numel(routes{vv}), numel(dp))
        [~, ~, mv] = congestion(C, routes{vv}{kk}, dp(kk));
        MU(end+1) = mv;
    end
end
if numel(MU) >= 3
    MU = sort(MU);
    cut1 = MU(max(1, round(numel(MU) / 3)));
    cut2 = MU(max(1, round(2 * numel(MU) / 3)));
else
    cut1 = 0.4; cut2 = 0.8;
end
logArr = zeros(20000, 5);
while toc(t0) < budget
    it = it + 1;
    el = toc(t0);

    % what to destroy, and which congestion regime it belongs to
    [allC, allV, allK, allI] = flatten(routes);
    if isempty(allC), break, end
    [g, clk] = pick_band(C, routes, allV, allK, allC, cut1, cut2);
    if ~useCong, g = 1; end

    if strcmp(pol, 'CBLNS')
        if useCong && mod(it, 20) == 1, bandMix = band_mix(C, routes); end
        s = state_of(C, routes, curF, bestF, f0, it, el, budget, bandMix);
        ai = choose_arm(Ainv, bvec, vbar, bbar, nUpd, s, it, d, delta);
        if rand < 0.05, ai = randi(nArms); end
    elseif strcmp(pol, 'ALNS')
        r = rand * sum(wgt); ai = 1;
        while ai < nArms && r > wgt(ai), r = r - wgt(ai); ai = ai + 1; end
    elseif strcmp(pol, 'VNS')
        ai = mod(it - 1, nArms) + 1;
    else
        ai = 3;                                     % Tabu uses random destruction
    end
    if onlyArm > 0, ai = onlyArm; end
    nPick(g, ai) = nPick(g, ai) + 1;
    logArr(it, :) = [it, clk, ai, g, bestF];

    if strcmp(pol, 'VNS')
        qq = [4 8 14]; q = qq(min(3, ceil(it / 300)));
    else
        q = 4 + floor(rand * 10);
    end
    [removed, cand] = destroy_routes(C, routes, arms{ai}, q);
    if isempty(removed), continue, end
    if strcmp(pol, 'TABU') && all(tabuUntil(removed) > it), continue, end

    [cand, okp] = repair_routes(C, cand, removed);
    if ~okp, continue, end
    [f, ~, okr] = routes_cost(C, cand);
    if ~okr, continue, end

    if el > 0.5
        Kest = max(200, it / max(0.02, el / budget));
    else
        Kest = budget * 40;
    end
    T = 0.002 * f0 * max(1e-3, (1 - it / Kest) ^ 2);
    sinceBest = sinceBest + 1;
    if sinceBest > 400 && curF > bestF * 1.01 + 1
        routes = best; curF = bestF; sinceBest = 0;
    end

    improved = f < curF - 1e-9;
    switch pol
        case 'TABU', accept = f < curF + 1e-9 || f < bestF - 1e-9;
        case 'ALNS', accept = improved;
        otherwise,   accept = improved || rand < exp(-(f - curF) / max(T, 1e-9));
    end

    if accept
        if strcmp(pol, 'CBLNS')
            rw = min(1, max(0, (curF - f) / f0));
            [Ainv, bvec, vbar, bbar, nUpd] = bandit_update( ...
                Ainv, bvec, vbar, bbar, nUpd, ai, s, rw);
        end
        if strcmp(pol, 'TABU'), tabuUntil(removed) = it + 15; end
        if strcmp(pol, 'ALNS')
            wus(ai) = wus(ai) + 1;
            if improved, wsc(ai) = wsc(ai) + 1; end
            if mod(it, 100) == 0
                for a = 1:nArms
                    if wus(a) > 0
                        wgt(a) = max(0.2, 0.8 * wgt(a) + 0.2 * (wsc(a) / wus(a) + 0.05));
                    end
                end
                wsc = zeros(1, nArms); wus = zeros(1, nArms);
            end
        end
        routes = cand; curF = f;
        if f < bestF - 1e-9, best = cand; bestF = f; sinceBest = 0; end
    end
end

routes = best;
out = describe(C, routes, bestF, nPick, it, true);
out.log = logArr(1:min(it, size(logArr,1)), :);
end


function m = band_mix(C, routes)
% share of driving time in each congestion regime, averaged over the trips
m = zeros(3,1); n = 0;
for v = 1:numel(routes)
    [okv, ~, ~, ~, ~, dep, ~] = route_eval(C, routes{v}, C.TSTART, C.B);
    if ~okv, continue, end
    for k = 1:min(numel(routes{v}), numel(dep))
        sh = congestion(C, routes{v}{k}, dep(k));
        m = m + sh(:); n = n + 1;
    end
end
if n > 0, m = m / n; else, m = [1/3; 1/3; 1/3]; end
end

function out = describe(C, routes, f, nPick, it, feasible)
[~, dd, ok, tr, sv] = routes_cost(C, routes);
out.feasible = ok && feasible;
out.obj = f; out.trips = tr; out.distance = dd; out.served = sv;
out.share = nPick; out.iters = it;
end


function [best, bestF] = ga_loop(C, F, seedRoutes, seedF, budget)
pop = 8;
P = cell(1, pop); Fv = zeros(1, pop);
P{1} = seedRoutes; Fv(1) = seedF;
for i = 2:pop
    ord = 2:C.n; ord = ord(randperm(numel(ord)));
    [r, ok, fv, ~] = build_routes(C, F, ord);
    if ~ok, P{i} = seedRoutes; Fv(i) = seedF; else, P{i} = r; Fv(i) = fv; end
end
[bestF, ib] = min(Fv); best = P{ib};
t0 = tic;
while toc(t0) < budget
    i = randi(pop); j = randi(pop);
    if Fv(i) > Fv(j), tmp = i; i = j; j = tmp; end
    child = P{i};
    if rand < 0.7
        [rm, child2] = destroy_routes(C, child, 'random', 4 + floor(rand * 10));
        if ~isempty(rm)
            [child2, okp] = repair_routes(C, child2, rm);
            if okp, child = child2; end
        end
    end
    [cf, ~, okr] = routes_cost(C, child);
    if ~okr, continue, end
    [~, w] = max(Fv);
    if cf < Fv(w)
        P{w} = child; Fv(w) = cf;
        if cf < bestF - 1e-9, best = child; bestF = cf; end
    end
end
end


function ai = choose_arm(Ai, bi, vb, bb, nu, s, it, d, delta)
at = sqrt(d * log(1 + it / delta)) / sqrt(max(1, it));
nArms = numel(Ai);
score = zeros(1, nArms);
for a = 1:nArms
    th = Ai{a} * bi{a};
    mu = th' * s;
    sd = sqrt(max(1e-12, s' * Ai{a} * s));
    if nu >= 5, score(a) = mu / vb + at * sd / bb;
    else,       score(a) = mu + at * sd; end
end
[~, ai] = max(score);
end


function [Ai, bi, vb, bb, nu] = bandit_update(Ai, bi, vb, bb, nu, ai, s, r)
z = Ai{ai} * s; den = 1 + s' * z;
Ai{ai} = Ai{ai} - (z * z') / den;
bi{ai} = bi{ai} + r * s;
th = Ai{ai} * bi{ai};
mu = abs(th' * s);
sd = sqrt(max(1e-12, s' * Ai{ai} * s));
nu = nu + 1;
if mu > 0, vb = (vb * (nu - 1) + mu) / nu; end
if bb > 0 && sd > 0, bb = (bb * (nu - 1) + sd) / nu; end
end


function s = state_of(C, routes, curF, bestF, f0, it, el, budget, bandMix)
d = 24; s = zeros(d, 1);
nt = 0; nst = 0; dl = 0; wsum = 0;
for v = 1:numel(routes)
    for k = 1:numel(routes{v})
        t = routes{v}{k};
        nt = nt + 1; nst = nst + numel(t);
        dl = dl + sum(C.demand(t));
    end
end
s(1) = min(1, nt / max(1, C.n / 3));
s(2) = min(1, dl / max(1, C.n * 200));
s(3) = min(1, curF / max(1, bestF));
s(4) = min(1, bestF / max(1, f0));
s(5) = min(1, it / 2000);
s(6) = min(1, el / max(1e-9, budget));
s(7) = double(curF <= bestF + 1e-9);
s(8:10) = bandMix(:);
s(11) = min(1, nst / max(1, nt));
s(12) = double(nt <= numel(routes));
s(13:24) = min(1, mod((1:12)', 3) / 3);    % filler, keeps the length at d = 24
s = min(1, max(0, s));
end


function [g, clk] = pick_band(C, routes, allV, allK, allC, cut1, cut2)
% the regime most of the destroyed customers' trips run in
cnt = zeros(1, 3); clkSum = 0; clkN = 0;
n = numel(allC);
sel = randperm(n, min(n, 6));
depCache = cell(1, numel(routes));
for i = sel
    v = allV(i); k = allK(i);
    if isempty(depCache{v})
        [okv, ~, ~, ~, ~, dep, ret] = route_eval(C, routes{v}, C.TSTART, C.B);
        if ~okv, depCache{v} = []; else, depCache{v} = (dep + ret) / 2; end
    end
    dep = depCache{v};
    if isempty(dep) || k > numel(dep), continue, end
    [~, ~, mv] = congestion(C, routes{v}{k}, dep(k));
        dom = 1 + (mv >= cut1) + (mv >= cut2);
    cnt(dom) = cnt(dom) + 1;
    clkSum = clkSum + dep(k); clkN = clkN + 1;
end
[~, g] = max(cnt);
if isempty(g), g = 1; end
if clkN > 0, clk = clkSum / clkN; else, clk = C.TSTART; end
end


function [allC, allV, allK, allI] = flatten(routes)
allC = []; allV = []; allK = []; allI = [];
for v = 1:numel(routes)
    for k = 1:numel(routes{v})
        for i = 1:numel(routes{v}{k})
            allC(end+1) = routes{v}{k}(i); %#ok<AGROW>
            allV(end+1) = v; %#ok<AGROW>
            allK(end+1) = k; %#ok<AGROW>
            allI(end+1) = i; %#ok<AGROW>
        end
    end
end
end


function [removed, cand] = destroy_routes(C, routes, mode, q)
[allC, allV, allK, allI] = flatten(routes);
n = numel(allC);
if n == 0, removed = []; cand = routes; return, end
q = min(q, n);
switch mode
    case 'random'
        sel = randperm(n, q);
    case 'worst'
        save = zeros(n, 1);
        for m = 1:n
            t = routes{allV(m)}{allK(m)};
            i = allI(m);
            a = 1; if i > 1, a = t(i-1); end
            b = 1; if i < numel(t), b = t(i+1); end
            save(m) = C.D(a, allC(m)) + C.D(allC(m), b) - C.D(a, b);
        end
        [~, ord] = sort(save, 'descend');
        sel = ord(1:q);
    otherwise   % sector
        ang = atan2(C.lat(allC) - C.lat(1), C.lon(allC) - C.lon(1));
        st = rand * 2 * pi;
        [~, ord] = sort(mod(ang - st, 2*pi));
        sel = ord(1:q);
end
removed = sort(allC(sel));
cand = routes;
for m = 1:q
    v = allV(sel(m)); k = allK(sel(m));
    for kk = numel(cand{v}):-1:1
        cand{v}{kk} = cand{v}{kk}(cand{v}{kk} ~= allC(sel(m)));
    end
end
for v = 1:numel(cand)
    empt = cellfun(@isempty, cand{v});
    cand{v} = cand{v}(~empt);
end
end


function [routes, ok] = repair_routes(C, routes, custs)
ok = true;
for q = 1:numel(custs)
    c = custs(q);
    bestD = Inf; bestV = 0; bestK = 0; bestP = 0;
    for v = 1:numel(routes)
        for k = 1:numel(routes{v})
            t = routes{v}{k};
            base = trip_dist(C, t);
            for p = 1:numel(t) + 1
                cand2 = [t(1:p-1), c, t(p:end)];
                R2 = routes{v}; R2{k} = cand2;
                [okr, ~, ~, ~, ~, ~, ~] = route_eval(C, R2, C.TSTART, C.B);
                if ~okr, continue, end
                dd = trip_dist(C, cand2) - base;
                if dd < bestD
                    bestD = dd; bestV = v; bestK = k; bestP = p;
                end
            end
        end
    end
    if bestV > 0
        t = routes{bestV}{bestK};
        routes{bestV}{bestK} = [t(1:bestP-1), c, t(bestP:end)];
        continue
    end
    placed = false;
    for v = 1:numel(routes)
        R2 = routes{v}; R2{end+1} = c;
        [okr, ~, ~, ~, ~, ~, ~] = route_eval(C, R2, C.TSTART, C.B);
        if okr, routes{v} = R2; placed = true; break, end
    end
    if ~placed, ok = false; return, end
end
end
