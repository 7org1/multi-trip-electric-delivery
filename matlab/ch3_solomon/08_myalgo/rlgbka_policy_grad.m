function g = rlgbka_policy_grad(pol, cache, a, adv, entBeta)
%RLGBKA_POLICY_GRAD  Gradient of log pi(a|s), optionally plus an entropy term.
%
%   g = rlgbka_policy_grad(pol, cache, a, adv)
%   g = rlgbka_policy_grad(pol, cache, a, adv, entBeta)
%
%   pol      weight struct (W1 b1 W2 b2 W3 b3)
%   cache    activations from rlgbka_policy(..., 'probs')
%   a        the action that was taken
%   adv      advantage  G_t - baseline
%   entBeta  weight of the entropy bonus (default 0)
%
%   g        struct with the same fields as pol
%
% SIGN CONVENTION
%   The result is added to the parameters (gradient ASCENT on the objective
%   adv * log pi + entBeta * H).  The caller must not negate it.
%
% THE SOFTMAX TERM
%   For logits z and p = softmax(z),   d log p(a)/dz = e_a - p.
%   The entropy gradient is                dH/dz      = -p .* (log p + H).
%   Both act on the same logits, so they are summed into one dz and propagated
%   through the network once.
%
% WHY THE ENTROPY TERM MATTERS HERE
%   With four actions and a decisive early reward, the policy collapses onto
%   route elimination within a few dozen updates and never explores the other
%   three again.  Checking the action frequency after training is the cheapest
%   way to detect that collapse; the entropy bonus is what prevents it.

    if nargin < 5 || isempty(entBeta), entBeta = 0; end

    A = size(pol.W3, 2);
    if a < 1 || a > A
        error('rlgbka_policy_grad:action', 'action %d outside 1..%d', a, A);
    end

    % ---- logits gradient: policy term
    dz = -cache.p;
    dz(a) = dz(a) + 1;
    dz = dz * adv;

    % ---- logits gradient: entropy term
    if entBeta > 0
        p = max(cache.p, 1e-12);
        H = -sum(p .* log(p));
        dz = dz + entBeta * (-p .* (log(p) + H));
    end

    % ---- output layer
    g.W3 = cache.h2' * dz;
    g.b3 = dz;

    % ---- second hidden layer
    dh2 = dz * pol.W3';
    dh2(cache.h2 <= 0) = 0;
    g.W2 = cache.h1' * dh2;
    g.b2 = dh2;

    % ---- first hidden layer
    dh1 = dh2 * pol.W2';
    dh1(cache.h1 <= 0) = 0;
    g.W1 = cache.s' * dh1;
    g.b1 = dh1;
end
