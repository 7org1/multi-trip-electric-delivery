function [pol, hist] = train_rlgbka(Pset, opts)
%TRAIN_RLGBKA  Train the operator-selection policy with REINFORCE plus baseline.
%
%   [pol, hist] = train_rlgbka(Pset, opts)
%
%   Pset   cell array of problem adapters (one per training instance)
%   opts   .episodes .batch .gamma .lr .hidden .budget .decideEvery
%          .entropy .clip .seed .verbose
%
%   pol    trained policy
%   log    .return .baseline .entropy .opFreq per update
%
% WHY REINFORCE AND NOT PPO
%   The action space has four elements.  PPO's clipping and GAE machinery exist
%   to stabilise updates in large action spaces with long horizons; here they add
%   implementation risk (a mis-scaled clip silently degrades learning) for little
%   benefit.  REINFORCE with a moving-average baseline is provably unbiased and
%   has three lines of code.  This should be stated in the paper rather than
%   left implicit.
%
% WHAT ONE EPISODE IS
%   One full run of the solver on one training instance, with the policy making
%   a decision every `decideEvery` iterations.  Returns are the discounted sum of
%   per-decision rewards, where a decision's reward is the improvement in the
%   penalised objective accumulated while that operator was in force.
%
% TRAINING BUDGET
%   Training episodes deliberately use a SHORTER evaluation budget than the
%   final experiments.  The policy learns when to switch operators, and that
%   decision structure is present at short budgets too, while a full-budget
%   episode costs an order of magnitude more.  The policy is evaluated at the
%   full budget afterwards; the schedule it learned is not budget-specific.

    if nargin < 2, opts = struct(); end
    opts = setdef(opts, 'episodes',     200);
    opts = setdef(opts, 'batch',          8);
    opts = setdef(opts, 'gamma',       0.99);
    opts = setdef(opts, 'lr',          3e-3);
    opts = setdef(opts, 'hidden',        64);
    opts = setdef(opts, 'budget',     20000);
    opts = setdef(opts, 'decideEvery',   20);
    opts = setdef(opts, 'entropy',     1e-3);
    opts = setdef(opts, 'clip',         1.0);
    opts = setdef(opts, 'seed',           1);
    opts = setdef(opts, 'verbose',     true);

    rng(opts.seed);
    pol = rlgbka_policy_init(struct('seed', opts.seed, 'hidden', opts.hidden));

    baseline = 0;
    buf = {};

    hist = struct('ret', [], 'base', [], 'ent', [], 'opFreq', []);

    for ep = 1:opts.episodes
        P = Pset{mod(ep-1, numel(Pset)) + 1};

        sOpts = struct('policy', pol, ...
                       'budget', opts.budget, ...
                       'decideEvery', opts.decideEvery, ...
                       'seed', ep, ...
                       'record', true, ...
                       'verbose', false);
        [~, out] = solve_rlgbka(P, sOpts);

        if ~isfield(out, 'traj') || numel(out.traj.A) == 0
            continue;
        end
        buf{end+1} = out.traj; %#ok<AGROW>

        if numel(buf) < opts.batch, continue; end

        % ------------------------------------------------------- update
        acc = zeroGrad(pol);
        rets = zeros(1, numel(buf));
        entAcc = 0; nStep = 0;
        freq = zeros(1, size(pol.W3, 2));

        for b = 1:numel(buf)
            tr = buf{b};
            rets(b) = sum(tr.r);
            G = discountedReturns(tr.r, opts.gamma);

            for t = 1:numel(tr.A)
                [~, p, cache] = rlgbka_policy(pol, tr.S(t, :), 'probs');
                adv = G(t) - baseline;

                g = rlgbka_policy_grad(pol, cache, tr.A(t), adv, opts.entropy);
                acc = addGrad(acc, g);

                entAcc = entAcc - sum(p .* log(max(p, 1e-12)));
                nStep = nStep + 1;

                freq(tr.A(t)) = freq(tr.A(t)) + 1;
            end
        end

        % average over the batch before clipping: the raw sum grows with the
        % batch size, and clipping the sum would make the effective step size
        % depend on how many episodes happened to be in the buffer
        acc = scaleGrad(acc, 1 / max(nStep, 1));
        acc = clipGrad(acc, opts.clip);
        pol = applyGrad(pol, acc, opts.lr);

        % ------------------------------------------------------- logging
        meanRet = mean(rets);
        baseline = 0.9 * baseline + 0.1 * meanRet;
        hist.ret(end+1)    = meanRet;
        hist.base(end+1)   = baseline;
        if nStep > 0
            hist.ent(end+1) = entAcc / nStep;
        else
            hist.ent(end+1) = 0;
        end
        hist.opFreq(end+1, :) = freq / max(sum(freq), 1);

        buf = {};

        if opts.verbose && mod(ep, 10) == 0
            fprintf('ep %4d  return %+.4f  baseline %+.4f  entropy %.3f  freq %s\n', ...
                    ep, meanRet, baseline, hist.ent(end), ...
                    mat2str(round(hist.opFreq(end, :) * 100) / 100));
        end
    end
end


% ================================================================ helpers

function o = setdef(o, f, v)
    if ~isfield(o, f), o.(f) = v; end
end

function G = discountedReturns(r, gamma)
    n = numel(r);
    G = zeros(n, 1);
    acc = 0;
    for t = n:-1:1
        acc = r(t) + gamma * acc;
        G(t) = acc;
    end
end

function g = zeroGrad(pol)
    g = struct();
    f = fieldnames(pol);
    for i = 1:numel(f)
        v = pol.(f{i});
        if isnumeric(v) && numel(v) > 1
            g.(f{i}) = zeros(size(v));
        end
    end
end

function a = addGrad(a, b)
    f = fieldnames(b);
    for i = 1:numel(f)
        a.(f{i}) = a.(f{i}) + b.(f{i});
    end
end

function g = scaleGrad(g, s)
    f = fieldnames(g);
    for i = 1:numel(f)
        g.(f{i}) = g.(f{i}) * s;
    end
end

function g = clipGrad(g, maxNorm)
%CLIPGRAD  Scale the whole gradient so its global L2 norm stays below maxNorm.
%
%   Clipping each parameter separately would distort the relative magnitudes
%   between layers, which is a common reason a training run "finishes" without
%   having learned anything.
    f = fieldnames(g);
    n2 = 0;
    for i = 1:numel(f)
        n2 = n2 + sum(g.(f{i})(:).^2);
    end
    nrm = sqrt(n2);
    if nrm > maxNorm
        s = maxNorm / nrm;
        for i = 1:numel(f)
            g.(f{i}) = g.(f{i}) * s;
        end
    end
end

function pol = applyGrad(pol, g, lr)
    f = fieldnames(g);
    for i = 1:numel(f)
        pol.(f{i}) = pol.(f{i}) + lr * g.(f{i});
    end
end
