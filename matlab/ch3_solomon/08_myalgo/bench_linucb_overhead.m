function bench_linucb_overhead()
%BENCH_LINUCB_OVERHEAD  How much of the 300 s budget would LinUCB spend on learning?
%
%   The comparison protocol is equal CPU time, and every scheduler runs its own
%   bookkeeping inside that time.  Round-robin spends nothing, adaptive weights
%   spend O(arms) per decision, and a contextual bandit spends O(arms * d^2).  The
%   question is whether that last term is visible next to the operators, which cost
%   16-20 ms each.
%
%   This simulates the decision loop alone -- no search -- for the number of
%   decisions a 300 s run actually produces, and reports the fraction of the budget
%   the learning would consume.

    d = 24;                 % state dimension
    A = 3;                  % three operators
    N = 20000;              % decisions in a 300 s run

    rng(1);
    S = rand(N, d);         % pretend states
    r = rand(N, 1);

    % ---- LinUCB with Sherman-Morrison inverse maintenance
    t0 = cputime;
    Ainv = repmat(eye(d), [1 1 A]);
    b = zeros(d, A);
    alpha = 0.5;
    for i = 1:N
        s = S(i, :).';
        p = zeros(1, A);
        for a = 1:A
            th = Ainv(:, :, a) * b(:, a);
            p(a) = th.' * s + alpha * sqrt(max(s.' * Ainv(:, :, a) * s, 0));
        end
        [~, pick] = max(p);
        Ai = Ainv(:, :, a);
        Ai_s = Ai * s;
        Ainv(:, :, pick) = Ai - (Ai_s * Ai_s.') / (1 + s.' * Ai_s);
        b(:, pick) = b(:, pick) + r(i) * s;
    end
    tUCB = cputime - t0;

    % ---- adaptive weights, for reference
    t0 = cputime;
    w = ones(1, A); sc = zeros(1, A); us = zeros(1, A);
    for i = 1:N
        cw = cumsum(w / sum(w));
        a = find(rand <= cw, 1, 'first');
        sc(a) = sc(a) + r(i); us(a) = us(a) + 1;
        if mod(i, 100) == 0
            for k = 1:A
                if us(k) > 0
                    w(k) = 0.9 * w(k) + 0.1 * (sc(k) / us(k));
                end
            end
            sc = zeros(1, A); us = zeros(1, A);
        end
    end
    tAW = cputime - t0;

    % ---- what the operators cost over the same number of decisions
    opMin = 16.0; opMax = 20.4;      % measured, ms per call
    tOp = N * (opMin + opMax) / 2 / 1000;

    fprintf('decisions simulated: %d\n\n', N);
    fprintf('%-22s %10s %12s\n', 'component', 'total s', 'share of 300 s');
    fprintf('%s\n', repmat('-', 1, 46));
    fprintf('%-22s %10.3f %11.4f%%\n', 'LinUCB (3 arms, d=24)', tUCB, 100*tUCB/300);
    fprintf('%-22s %10.3f %11.4f%%\n', 'adaptive weights', tAW, 100*tAW/300);
    fprintf('%-22s %10.1f %11.2f%%\n', 'operators (16-20 ms)', tOp, 100*tOp/300);
    fprintf('\nLinUCB as a fraction of operator time: %.4f%%\n', 100*tUCB/tOp);

    % ---- how many decisions are lost to the learning overhead
    perDec = (tUCB) / N;
    fprintf('extra per decision: %.1f us\n', perDec*1e6);
    fprintf('decisions lost in 300 s if each costs ~12 ms: %.0f of %.0f\n', ...
            300/perDec * 0, 300/0.012);
end
