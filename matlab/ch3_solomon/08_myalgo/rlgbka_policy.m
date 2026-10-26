function [a, p, cache] = rlgbka_policy(pol, s, mode)
%RLGBKA_POLICY  Forward pass of the operator-selection policy, and sampling.
%
%   [a, p, cache] = rlgbka_policy(pol, s)          sample an action
%   [a, p, cache] = rlgbka_policy(pol, s, 'greedy') take the most likely one
%   [~, p, cache] = rlgbka_policy(pol, s, 'probs') only the probabilities
%
%   pol    weight struct from rlgbka_policy_init
%   s      1x24 state from rlgbka_features
%   a      chosen operator index 1..8
%   p      1x8 action probabilities
%   cache  intermediate activations, needed for the gradient during training
%
% NUMERICAL NOTE
%   The softmax is computed after subtracting the maximum logit.  Without that
%   shift, exp() of a large logit returns Inf and the gradient becomes NaN; it
%   happens easily once the weights have grown during training.

    if nargin < 3, mode = 'sample'; end

    s = s(:)';
    h1 = s * pol.W1 + pol.b1;   h1 = max(h1, 0);
    h2 = h1 * pol.W2 + pol.b2;  h2 = max(h2, 0);
    z  = h2 * pol.W3 + pol.b3;

    z = z - max(z);
    e = exp(z);
    p = e / sum(e);

    cache = struct('s', s, 'h1', h1, 'h2', h2, 'p', p);

    switch lower(mode)
        case 'probs'
            a = 0;
        case 'greedy'
            [~, a] = max(p);
        otherwise
            c = cumsum(p);
            a = find(rand <= c, 1, 'first');
            if isempty(a), a = numel(p); end
    end
end
