function test_policy_grad()
%TEST_POLICY_GRAD  Finite-difference check of the policy gradient.
%
%   A wrong backpropagation does not crash and does not produce obviously broken
%   output: training simply improves nothing, and the failure looks like "RL does
%   not help on this problem" rather than "the gradient is wrong".  This test
%   compares the analytic gradient against a central finite difference, which
%   catches sign errors, missing ReLU masks and mis-transposed matrices.

    here = fileparts(mfilename('fullpath'));
    addpath(here);

    rng(0);
    pol = rlgbka_policy_init(struct('seed', 0, 'hidden', 8));
    s   = rand(1, pol.d) * 0.5;
    a   = 3;
    adv = 1.7;

    [~, ~, cache] = rlgbka_policy(pol, s, 'probs');
    g = rlgbka_policy_grad(pol, cache, a, adv);

    % objective whose gradient we are checking: adv * log pi(a|s)
    fh = @(p) adv * log(probOf(p, s, a));

    fprintf('analytic vs finite-difference gradient\n');
    fprintf('%-6s %14s %14s %12s\n', 'field', 'analytic', 'numeric', 'rel.err');
    fprintf('%s\n', repmat('-', 1, 50));

    worst = 0;
    fields = {'W1','b1','W2','b2','W3','b3'};
    for fi = 1:numel(fields)
        f = fields{fi};
        P = pol.(f);
        G = g.(f);
        nCheck = min(numel(P), 25);          % sample, do not check all
        idx = randperm(numel(P), nCheck);
        for k = 1:nCheck
            i = idx(k);
            h = 1e-6;
            Pp = pol; Pp.(f)(i) = P(i) + h;
            Pm = pol; Pm.(f)(i) = P(i) - h;
            num = (fh(Pp) - fh(Pm)) / (2*h);
            ana = G(i);
            rel = abs(num - ana) / max(abs(num) + abs(ana), 1e-9);
            worst = max(worst, rel);
            if k <= 3
                fprintf('%-6s %14.8f %14.8f %12.2e\n', f, ana, num, rel);
            end
        end
    end

    fprintf('\nmax relative error over all sampled entries: %.2e\n', worst);
    if worst < 1e-5
        fprintf('GRADIENT CHECK PASSED\n');
    else
        fprintf('GRADIENT CHECK FAILED -- backprop is wrong\n');
    end
end

function p = probOf(pol, s, a)
    [~, pp, ~] = rlgbka_policy(pol, s, 'probs');
    p = pp(a);
end
