function pol = rlgbka_policy_init(opts)
%RLGBKA_POLICY_INIT  Initial weights for the operator-selection policy.
%
%   pol = rlgbka_policy_init()
%   pol = rlgbka_policy_init(struct('seed', 3, 'hidden', 64))
%
%   The network is  24 -> hidden -> hidden -> 8  with ReLU and a softmax head.
%   With the default hidden width of 64 that is 6,344 parameters, which is small
%   enough that a full forward pass costs a few microseconds and training on a
%   CPU is a matter of minutes.
%
%   Initialisation is He-style (scale sqrt(2/fan_in)), the usual choice for
%   ReLU stacks.  A zero-initialised ReLU network would output a constant
%   distribution and receive no gradient signal at all, so the random start is
%   functional, not cosmetic.
%
%   A SMALL PRIOR IS BAKED IN
%   The final bias is set so operator 6 (light refinement) and operator 4
%   (route elimination) start slightly favoured.  An uninformed policy wastes
%   most of its early budget on operator 3 (remove half the customers), which
%   rarely helps.  The prior only shifts the starting point; training is free to
%   overturn it.

    if nargin < 1, opts = struct(); end
    if ~isfield(opts, 'seed'),   opts.seed = 1;   end
    if ~isfield(opts, 'hidden'), opts.hidden = 64; end
    if ~isfield(opts, 'A'),      opts.A = 8;      end

    rng(opts.seed);
    d = 24; H = opts.hidden; A = opts.A;

    pol = struct();
    pol.d = d; pol.H = H; pol.A = A;
    pol.hidden = H;

    pol.W1 = randn(d, H) * sqrt(2 / d);
    pol.b1 = zeros(1, H);
    pol.W2 = randn(H, H) * sqrt(2 / H);
    pol.b2 = zeros(1, H);
    pol.W3 = randn(H, A) * sqrt(2 / H);
    pol.b3 = zeros(1, A);

    prior8 = [0 0 -0.3 0.4 0 0.4 0.1 0.2];
    if A == 8
        pol.b3 = pol.b3 + prior8;
    else
        % keep the same relative preference, sampled onto the available actions
        pol.b3 = pol.b3 + linspace(-0.1, 0.3, A);
    end
end
