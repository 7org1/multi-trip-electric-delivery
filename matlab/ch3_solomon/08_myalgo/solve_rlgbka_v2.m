function [best, out] = solve_rlgbka_v2(P, opts)
%SOLVE_RLGBKA_V2  Byte-identical copy of solve_rlgbka_online plus three more schedulers.
%
%   WHY A COPY AND NOT AN EDIT
%   The A/B/C sweep is running while these schedulers are being added.  MATLAB caches
%   parsed functions per session, so editing solve_rlgbka_online.m mid-sweep would let
%   some runs pick up the new code and others not -- the same experiment would end up
%   containing two versions of the solver.  This file is that same solver plus:
%
%       mode='pure'      always the same operator (the zero-information control)
%       mode='thompson'  linear Thompson sampling: exploration from the posterior
%       opts.alphaMode='sched'  the alpha_t schedule from linear-bandit theory
%
%   Everything else, including the determinism fix and the time-normalised reward, is
%   unchanged, so results are comparable across the two files.
%
%   [best, out] = solve_rlgbka_online(P, opts)
%
%   opts.timeLimit   CPU seconds, default 300
%   opts.seed        RNG seed, default 1
%   opts.vehWeight   vehicle weight, default 1e4
%   opts.opSet       operator ids, default 1:8
%   opts.decideEvery decisions per iteration are 1; kept for parity with the
%                    offline solver (must be 1 here, see below)
%   opts.gamma       discount, default 0.99
%   opts.window      n-step return length, default 50
%   opts.lr          learning rate, default 2e-3
%   opts.entropy     entropy bonus, default 1e-3
%   opts.lamLo       lower clamp on the penalty multipliers.  This floor is not
%                    cosmetic: with it near zero the policy can drive lambda down,
%                    the search then wanders permanently infeasible, the repair
%                    falls back to penalised insertion on almost every call, and
%                    the iteration rate collapses along with the solution quality.
%                    Measured with a floor of [1 0.5]: 624 iterations in 300 s and
%                    no improvement over the construction at all.
%   opts.lamHi       upper clamp
%   opts.verbose     default false
%
% WHAT IS LEARNED, AND WHERE THE LEARNING HAPPENS
%   Two linear heads over a 24-dimensional state:
%       head A  -> which of the |opSet| operators to apply
%       head B  -> whether to loosen, hold or tighten the penalty multipliers
%   Parameters: 24*|opSet| + |opSet| + 24*3 + 3 = 275 for eight operators.
%
%   The policy is updated after EVERY iteration, from within the same CPU budget
%   as the search.  There is no offline training step and therefore no question
%   of an unequal offline advantage over the baselines.
%
% WHY DECISIONS ARE MADE EVERY ITERATION
%   An earlier design decided every 20 iterations, which yields only about 600
%   samples in a 300 s budget -- far too few to estimate even a linear policy.
%   At one decision per iteration the same budget provides roughly 10,000
%   samples, which is enough.  A linear update costs microseconds against
%   milliseconds for the operator itself, so the learning overhead is under 1%
%   of the budget.
%
% THE TWO HEAD DESIGN, AND WHY NOT A JOINT ACTION SPACE
%   Eight operators times three penalty steps is 24 joint actions, i.e. 576
%   parameters, which the same sample budget cannot estimate.  Factoring the two
%   decisions into separate heads sharing one state keeps it at 275 parameters
%   while still allowing the policy to condition the penalty step on what it is
%   about to do, through the shared state.
%
% REWARD IS COMPUTED ON A FIXED REFERENCE PENALTY
%   The search accepts moves using the ADAPTIVE lambda that the policy controls.
%   The reward, however, is the improvement in an objective that uses a FIXED
%   reference lambda.  Without this, the policy could lower lambda, make
%   violations cheap, and collect reward for a smaller value of an objective it
%   is itself redefining.  That is reward hacking, not optimisation, and it
%   reliably drives the search into permanent infeasibility.

    if nargin < 2, opts = struct(); end
    opts = setdef(opts, 'timeLimit',  300);
    opts = setdef(opts, 'seed',         1);
    opts = setdef(opts, 'vehWeight',  1e4);
    opts = setdef(opts, 'opSet',       1:8);
    opts = setdef(opts, 'gamma',      0.99);
    opts = setdef(opts, 'window',       50);
    opts = setdef(opts, 'lr',         2e-3);
    opts = setdef(opts, 'entropy',    1e-3);
    opts = setdef(opts, 'clip',         1.0);
    opts = setdef(opts, 'lamCap0',      50);
    opts = setdef(opts, 'lamTw0',        5);
    opts = setdef(opts, 'lamStart', [50 5]);   % loose, but not so loose that feasibility is abandoned
    opts = setdef(opts, 'lamLo',  [10 5]);
    opts = setdef(opts, 'lamHi',  [200 500]);
    opts = setdef(opts, 'eliteSize',     8);
    opts = setdef(opts, 'verbose',   false);
    opts = setdef(opts, 'dtRef',      0.05);   % reference action duration for reward normalisation
    opts = setdef(opts, 'T0scale',    0.002);  % near-greedy: SA at a larger T lost the descent
    opts = setdef(opts, 'Tref',      'dist'); % 'dist' near-greedy | 'obj' ALNS-style
    opts = setdef(opts, 'pInfeasible', 0.0);   % never accept infeasible: measured to be the single largest defect
    opts = setdef(opts, 'useScaleHead', true);
    opts = setdef(opts, 'mode', 'learned');   % learned | roundrobin | handrule
    opts = setdef(opts, 'opFun', @rlgbka_ops); % operator dispatcher
    opts = setdef(opts, 'samplePool', 0);      % >0: collect routes every N iterations
    opts = setdef(opts, 'nIterExpected', 20000); % for the annealing schedule, in iterations
    opts = setdef(opts, 'segLength', 100);     % adaptive weights: iterations per update
    opts = setdef(opts, 'reaction', 0.1);      % adaptive weights: decay
    opts = setdef(opts, 'scores', [33 9 13 0]); % new best / better / accepted / rejected
    opts = setdef(opts, 'alpha', 0.5);         % LinUCB exploration weight
    opts = setdef(opts, 'alphaMode', 'const'); % 'const' | 'sched' (theory-driven)
    opts = setdef(opts, 'pureArm', 2);         % arm used by mode='pure'
    opts = setdef(opts, 'alphaScale', 1);      % multiplies the exploration bonus
    opts = setdef(opts, 'rewardScale', 1);     % multiplies the normalised reward
    opts = setdef(opts, 'alphaDecay', 'theory'); % 'theory' | 'fast' (1/sqrt(n))
    opts = setdef(opts, 'standardize', false); % normalise both terms by running means

    rng(opts.seed);
    ctr = cpu_budget(opts.timeLimit);

    opSet = opts.opSet(:)';
    nA = numel(opSet);
    nL = 3;                                  % loosen / hold / tighten
    vehW = opts.vehWeight;

    lamRef = struct('cap', opts.lamCap0, 'tw', opts.lamTw0);   % fixed, for reward
    lam    = lamRef;                                            % adaptive, for search

    % ---- linear policy, zero-initialised (uniform to begin with)
    Wop = zeros(24, nA);  bop = zeros(1, nA);
    Wlm = zeros(24, nL);  blm = zeros(1, nL);

    % adaptive weights (Ropke & Pisinger form), used when mode is 'adaptive'
    wts  = ones(1, nA);
    sc   = zeros(1, nA);
    uses = zeros(1, nA);

    % LinUCB state, used when mode is 'linucb'
    Ainv    = repmat(eye(24), [1 1 nA]);
    bA      = zeros(24, nA);
    rAbsAvg = 0;
    valBar  = 1;   % running mean of |value term|, for opts.standardize
    bonBar  = 1;   % running mean of the bonus, for opts.standardize

    % ---- start
    x = P.construct();
    [fx, Rx] = vrp_objective(P, x, lam, vehW);
    ctr.hit();
    gPrev = Rx.dist + vehW * Rx.nveh;
    scale = max(Rx.dist, 1);

    elite = {x}; eliteKey = [Rx.nveh, Rx.dist];
    isNewBest = false;
    best = {}; bestKey = [inf inf];
    if Rx.feasible
        best = x; bestKey = [Rx.nveh, Rx.dist];
    end

    recentUse = zeros(1, 8); recentSucc = zeros(1, 8);
    opUse = zeros(1, 8);  opSucc = zeros(1, 8);
    stagnation = 0; windowStag = 200;

    % ---- n-step return buffer
    Wd = opts.window;
    bufS = zeros(Wd, 24); bufAo = zeros(Wd, 1); bufAl = zeros(Wd, 1);
    bufR = zeros(Wd, 1); nBuf = 0;
    baseline = 0;
    lr = opts.lr;
    curve = [];
    pool = {}; poolMap = containers.Map('KeyType','char','ValueType','logical');

    while ~ctr.exhausted()
        ctr.tick();

        % ---------------------------------------------------- observe state
        if mod(ctr.nIter, 100) == 1 || ctr.nIter == 1
            eliteDiv = diversityOf(elite, scale);
        end
        s = buildState(fx, bestKey(2), scale, stagnation, windowStag, Rx, P, ...
                       eliteKey, eliteDiv, recentSucc, recentUse);

        % ---------------------------------------------------- act
        op_g = s * Wop + bop;   op_g = op_g - max(op_g);
        p_op = exp(op_g); p_op = p_op / sum(p_op);
        ai = sample(p_op);

        lm_g = s * Wlm + blm;   lm_g = lm_g - max(lm_g);
        p_lm = exp(lm_g); p_lm = p_lm / sum(p_lm);
        bi = sample(p_lm);

        % ---------------------------------------------- comparison policies
        %
        % The three configurations differ ONLY in how the operator is chosen:
        %   learned     the policy above
        %   roundrobin  every operator equally often, no learning
        %   handrule    all four for the first third of the budget, then only the
        %               cheap ones -- the rule a practitioner reaches for once told
        %               that route elimination is expensive
        %
        % The comparison is meaningful only because the cost asymmetry is real:
        % route elimination measured 207 ms against 5.6 ms for the string move, so
        % a uniform schedule spends 87% of the budget on one operator.
        switch opts.mode
            case 'pure'
                % THE ZERO-INFORMATION CONTROL.
                % Always the same operator, chosen by opts.pureArm.  If this matches the
                % learned schedulers, the learning has collapsed to a constant and adds
                % nothing; that is the most important comparison in the whole study, and
                % it costs one line to run.
                ai = opts.pureArm;
                bi = 2;
            case 'thompson'
                % Linear Thompson sampling.
                %
                % UCB locks on because its bonus is alpha*sqrt(s' A^-1 s) and A grows
                % with every pull, so the bonus dies and the argmax freezes.  Sampling
                % the posterior explores in proportion to the remaining uncertainty,
                % with no exploration parameter at all: rewards are normalised by a
                % running mean of their own magnitude, so the noise scale is one and
                % there is nothing to tune.  It is stochastic, but with a fixed seed it
                % is still exactly reproducible.
                pArm = zeros(1, nA);
                for a = 1:nA
                    th = Ainv(:, :, a) * bA(:, a);
                    Lc = chol(Ainv(:, :, a) + 1e-10 * eye(24), 'lower');
                    thS = th + Lc * randn(24, 1);
                    pArm(a) = thS.' * s(:);
                end
                [~, ai] = max(pArm);
                bi = 2;
            case 'linucb'
                % Linear UCB over the operator arms.
                %
                % WHY THIS INSTEAD OF THE POLICY GRADIENT
                % REINFORCE needs thousands of samples per parameter to separate a
                % gradient from its own noise, and a 300 s run yields 15,000-25,000
                % decisions of which only 130-400 carry a positive reward.  LinUCB
                % is a closed-form ridge regression per arm with an explicit
                % exploration bonus, so it uses the same samples far better, and its
                % argmax is deterministic -- which matters now that the run is meant
                % to be reproducible.
                %
                % Measured cost: 146 us per decision, 2.9 s over 20,000 decisions,
                % i.e. about 1% of the 300 s budget and 0.8% of the operator time.
                % Three arms of dimension 24 is 72 parameters in total.
                % alpha_t grows with the horizon, which is what stops the bonus from
                % dying as A accumulates.  The reference bound is sqrt(d ln(1+t/delta))
                % with the conventional delta = 0.05, so this is a schedule fixed by
                % theory rather than a constant that has to be tuned.
                if strcmp(opts.alphaMode, 'sched')
                    aT = sqrt(24 * log(1 + ctr.nIter / 0.05));
                else
                    aT = opts.alpha;
                end
                aT = aT * opts.alphaScale;

                % V2: force the bonus to decay as 1/n instead of sqrt(ln t / n).
                % The theoretical width keeps the bonus 50-130 times larger than the
                % value term for the whole run, which turns the argmax into "pick the
                % least sampled arm" and therefore into uniform rotation.  Dividing by
                % sqrt(n) makes exploration die out instead of persisting.
                if strcmp(opts.alphaDecay, 'fast')
                    aT = aT / sqrt(max(ctr.nIter, 1));
                end

                pArm = zeros(1, nA);
                if opts.standardize
                    % V3: put both terms on a common scale so that alpha means what it
                    % says.  The value term is 50-130 times smaller than the bonus in
                    % raw units, so their ratio is invisible in alpha; normalising each
                    % by a running mean of its own magnitude makes alpha = 0.5 an
                    % actual balance between the two.
                    val = zeros(1, nA); bon = zeros(1, nA);
                    for a = 1:nA
                        th = Ainv(:, :, a) * bA(:, a);
                        q  = max(s(:).' * Ainv(:, :, a) * s(:), 0);
                        val(a) = th.' * s(:);
                        bon(a) = sqrt(q);
                    end
                    valBar = 0.99 * valBar + 0.01 * mean(abs(val));
                    bonBar = 0.99 * bonBar + 0.01 * mean(bon);
                    pArm = val / max(valBar, 1e-12) + aT * bon / max(bonBar, 1e-12);
                else
                    for a = 1:nA
                        th = Ainv(:, :, a) * bA(:, a);
                        q  = max(s(:).' * Ainv(:, :, a) * s(:), 0);
                        pArm(a) = th.' * s(:) + aT * sqrt(q);
                    end
                end
                [~, ai] = max(pArm);
                bi = 2;
            case 'adaptive'
                % roulette wheel over the weights
                cw = cumsum(wts / sum(wts));
                ai = find(rand <= cw, 1, 'first');
                if isempty(ai), ai = nA; end
                bi = 2;
            case 'roundrobin'
                ai = mod(ctr.nIter, nA) + 1;
                bi = 2;                       % scale x1
            case 'handrule'
                if ctr.elapsed() < opts.timeLimit / 3 || nA < 4
                    ai = randi(nA);
                else
                    ai = 1 + randi(nA - 1);   % skip action 1 (route elimination): 2..nA
                end
                bi = 2;
        end

        % --------------------------------------- operator scale from policy
        %
        % THIS IS THE COUPLING.
        % The policy does not merely choose an operator; it also chooses how far
        % that operator reaches.  A destroy step at scale 0.5 is a local nudge, at
        % scale 2.0 it is a structural rewrite, and a block move of length two is
        % a different neighbourhood from one of length twelve.  Operator identity
        % and operator magnitude are therefore decided together, and neither is a
        % fixed rule that a reviewer could substitute.
        %
        % The penalty is held constant.  Annealing it was measured to fail at both
        % ends -- at the ceiling every destroy-repair candidate violated something
        % and was rejected, freezing the search; at the floor violations became
        % free and the search "improved" the penalised objective 134,067 times
        % without improving a single feasible solution.  Accepting infeasible
        % candidates at all turned out to be the single largest defect: with it,
        % C1_2_1 managed 5 improvements and 21 vehicles; without it, 25
        % improvements and 20 vehicles.
        switch bi
            case 1, opScale = 0.5;
            case 2, opScale = 1.0;
            otherwise, opScale = 2.0;
        end
        if ~opts.useScaleHead, opScale = 1.0; end

        lam.cap = opts.lamStart(1);
        lam.tw  = opts.lamStart(2);

        % ------------------------------------------- apply operator
        opId = opSet(ai);
        tOp = cputime;
        ctx = struct('lam', lam, 'ctr', ctr, 'elite', {elite}, ...
                     'vehWeight', vehW, 'scale', opScale);
        [cand, ~] = opts.opFun(opId, P, x, ctx);
        [fc, Rc] = vrp_objective(P, cand, lam, vehW);
        ctr.hit();

        % ------------------------------------------------- completeness gate
        %
        % AN OPERATOR THAT DROPS A CUSTOMER PRODUCES A CANDIDATE THAT LOOKS EXCELLENT.
        % Fewer customers means less distance and no violations, so the objective
        % reports an improvement and the search takes it.  Every repair takes a
        % failure path that can return the customers it could not place, and nothing
        % downstream was checking: on R1_2_1 the search recorded 147 "improvements"
        % per run and never once beat the constructive solution, because every one of
        % them was a solution serving fewer than 200 customers.  Route elimination was
        % the worst offender -- it produced 1 vehicle at distance 318 serving 12
        % customers, which the incumbent comparison read as a 93% gain over the best
        % known solution.
        %
        % A candidate that does not serve every customer exactly once is therefore
        % discarded here, before it can enter the search.  The scan is O(n) and costs
        % a few microseconds against milliseconds for the operator itself.
        if ~servesAll(cand, P.n)
            fc = inf;
            Rc.feasible = false;
            Rc.nveh = inf;
            Rc.dist = inf;
            Rc.capExcess = inf;
            Rc.twExcess = inf;
        end

        % ---- route pool: every feasible candidate, not just the accepted one.
        % Sampling the incumbent gave 687 distinct routes in 22,504 iterations --
        % a near-greedy search keeps revisiting the same routes, so the pool held
        % essentially one neighbourhood and set partitioning had nothing to
        % recombine.  Collecting every feasible candidate instead puts all the
        % routes the search ever built into the pool, which is what the route-pool
        % literature does.
        if opts.samplePool > 0 && Rc.feasible && mod(ctr.nIter, opts.samplePool) == 0
            for rr = 1:numel(cand)
                key = sprintf('%d,', cand{rr});
                if ~isKey(poolMap, key)
                    poolMap(key) = true;
                    pool{end+1} = cand{rr}; %#ok<AGROW>
                end
            end
        end
        % ---------------------------------------------------- accept
        %
        % ACCEPTANCE IS DECIDED ON g = distance + vehWeight*vehicles, NOT ON THE
        % PENALISED OBJECTIVE.
        % A move that merely reduces the violation trace improves the penalised
        % objective while leaving the real solution worse, so an acceptance rule
        % written on it lets the search trade violations against nothing and
        % drift away from a good incumbent.  Measured with the old rule on
        % C1_2_1: four improvements in 13,000 iterations.  Measured with a plain
        % greedy descent on g and the same four operators: 36 improvements
        % reaching 20 vehicles and 2801 from 3177, inside the same 300 s.
        %
        % A feasible candidate is accepted when it improves g, or with the
        % annealing probability when it does not.  An infeasible candidate is
        % accepted only while the search is still allowed to explore -- the
        % tolerance decays with the budget -- because that is the only way to
        % cross a barrier whose two sides are both feasible.
        % PROGRESS IS MEASURED IN ITERATIONS, NOT IN SECONDS.
        % The annealing schedule used to read ctr.elapsed(), which is wall-clock-like
        % CPU time: two runs with the same seed took different trajectories whenever
        % the machine was loaded differently, and a repeat of one configuration gave
        % 22/5590 instead of 22/5377.  Nothing below can be reported with a variance
        % until that is fixed.  nIterExpected is calibrated from a pilot run; if the
        % real budget yields more iterations the schedule simply finishes earlier,
        % which is harmless because the temperature is already near zero.
        frac = max(0, 1 - ctr.nIter / max(opts.nIterExpected, 1));
        switch opts.Tref
            case 'dist'
                T = opts.T0scale * max(Rx.dist, 1) / log(2) * frac^2;
            otherwise
                % ALNS-style: the temperature is scaled to the penalised objective,
                % which contains vehWeight * vehicles and is therefore thousands of
                % times larger than the distance.  Early moves are then almost all
                % accepted, which is what lets a search leave a constructive
                % solution that no single move improves.
                T = opts.T0scale * max(abs(fx), 1) / log(2) * frac^2;
        end

        gc = Rc.dist + vehW * Rc.nveh;
        if Rc.feasible
            accepted = (gc < gPrev - 1e-9) || ...
                       (rand < exp(-(gc - gPrev) / max(T, 1e-9)));
        else
            accepted = (fc < fx - 1e-9) && (rand < opts.pInfeasible * frac);
        end

        if isfield(opts,'debug') && opts.debug && ctr.nIter <= 12
            fprintf('  it%3d op%d scale%.1f feas%d gc%.0f gPrev%.0f T%.1f acc%d nveh%d\n', ...
                ctr.nIter, opId, opScale, Rc.feasible, gc, gPrev, T, accepted, Rc.nveh);
            fprintf('      servesAll=%d  total=%d  n=%d  maxID=%d  minID=%d\n', servesAll(cand,P.n), sum(cellfun(@numel,cand)), P.n, max(cellfun(@max,cand)), min(cellfun(@min,cand)));
        end

        % Reward is measured on the REFERENCE objective, so the policy cannot
        % earn reward by redefining the penalty it just moved.
        % ---------------------------------------------- reward on the REAL goal
        %
        % g = distance + vehWeight * vehicles, the quantity actually reported.
        % No penalty terms: rewarding the penalised objective let the policy earn
        % 134,067 "improvements" by trading distance against violations without
        % ever producing a better feasible solution.
        %
        % r > 0 only when the candidate is feasible AND improves g.  The signal
        % is sparse on purpose.  It is also the only signal that cannot be gamed:
        % neither the policy, nor lambda, nor the acceptance rule can make a
        % feasible solution look better than it is.
        dtOp = max(cputime - tOp, 1e-4);
        r = 0;
        if accepted
            if Rc.feasible && (gc < gPrev - 1e-9)
                % TIME-NORMALISED REWARD
                % The budget is time, not decisions.  A cheap operator can be
                % applied far more often than an expensive one, so a per-decision
                % reward lets it farm many small gains and the policy collapses
                % onto it: measured at 786,570 of 786,785 decisions on string
                % move alone, which is 99.97%.  Dividing by the CPU time the
                % action consumed turns the objective into "improvement per unit
                % of the budget", which is the quantity the comparison actually
                % cares about.  This is the standard semi-MDP treatment, with the
                % action duration appearing in the reward.
                r = (gPrev - gc) / scale * (opts.dtRef / dtOp);
            end
            x = cand; fx = fc; Rx = Rc; gPrev = gc;
        end

        % ---------------------------------------------------- bookkeeping
        recentUse(ai) = recentUse(ai) + 1;
        if r > 0
            recentSucc(ai) = recentSucc(ai) + 1;
            opSucc(ai) = opSucc(ai) + 1;
        end
        opUse(ai) = opUse(ai) + 1;

        if Rc.feasible
            key = [Rc.nveh, Rc.dist];
            % COMPLETENESS GUARD
            % A solution can be "feasible" -- no capacity excess, no window excess --
            % while serving fewer than all customers, if an operator drops some.  That
            % is exactly what route elimination did before its failure path was fixed:
            % it produced 1 vehicle at distance 318 serving 12 of 200 customers, which
            % this comparison would have recorded as a 93% improvement over the best
            % known.  Every incumbent is therefore checked for complete coverage before
            % it can be recorded.  The check is O(n) but runs only when a candidate
            % would actually replace the incumbent, so it costs nothing in the loop.
            if lexBetter(key, bestKey) && servesAll(cand, P.n)
                best = cand; bestKey = key; stagnation = 0;
                isNewBest = true;
            else
                stagnation = stagnation + 1;
            end
            [elite, eliteKey] = pushElite(elite, eliteKey, cand, key, opts.eliteSize);
        else
            stagnation = stagnation + 1;
        end

        % ------------------------------------------------- adaptive weights
        %
        % Ropke & Pisinger's scheme, with the values from the original paper and no
        % tuning: a segment of segLength iterations accumulates a score per operator
        % (33 for a new global best, 9 for an improvement on the current solution, 13
        % for an accepted but worse solution, 0 otherwise), and at the end of the
        % segment each weight is pulled towards that operator's average score with
        % decay rho.  Selection in the next segment is a roulette wheel on the weights.
        %
        % This is a stateless bandit: it tracks how well each operator has been doing
        % but not what the search looks like.  Against it, a state-conditioned policy
        % has to demonstrate that the state carries information the average yield does
        % not.  That comparison is the only one that can justify learning a policy.
        if strcmp(opts.mode, 'adaptive')
            if isNewBest
                sOp = opts.scores(1);
            elseif accepted && (gc < gPrev - 1e-9)
                sOp = opts.scores(2);
            elseif accepted
                sOp = opts.scores(3);
            else
                sOp = opts.scores(4);
            end
            sc(ai)   = sc(ai) + sOp;
            uses(ai) = uses(ai) + 1;

            if mod(ctr.nIter, opts.segLength) == 0
                for kk = 1:nA
                    if uses(kk) > 0
                        wts(kk) = (1 - opts.reaction) * wts(kk) ...
                                  + opts.reaction * (sc(kk) / uses(kk));
                    end
                end
                wts = max(wts, 1e-6);
                sc = zeros(1, nA); uses = zeros(1, nA);
            end
        end
        isNewBest = false;

        % ------------------------------------------------- LinUCB update
        %
        % The reward is the same time-normalised improvement the policy gradient
        % used, divided by a running mean of its own magnitude so that the
        % exploration weight alpha does not have to be retuned when the instance or
        % the cost scale changes.  Sherman-Morrison keeps the inverse current in
        % O(d^2) instead of refactorising every step.
        if strcmp(opts.mode, 'linucb') || strcmp(opts.mode, 'thompson')
            rAbsAvg = 0.99 * rAbsAvg + 0.01 * abs(r);
            rn = r / max(rAbsAvg, 1e-12) * opts.rewardScale;
            sv = s(:);
            Ai = Ainv(:, :, ai);
            Ai_s = Ai * sv;
            Ainv(:, :, ai) = Ai - (Ai_s * Ai_s.') / (1 + sv.' * Ai_s);
            bA(:, ai) = bA(:, ai) + rn * sv;
        end

        if mod(ctr.nIter, 50) == 0
            recentUse = recentUse * 0.5; recentSucc = recentSucc * 0.5;
        end



        % ---------------------------------------------------- online update
        nBuf = nBuf + 1;
        bufS(nBuf, :) = s; bufAo(nBuf) = ai; bufAl(nBuf) = bi; bufR(nBuf) = r;

        if nBuf == Wd
            G = 0;
            for k = Wd:-1:1
                G = bufR(k) + opts.gamma * G;
            end
            adv = G - baseline;
            baseline = 0.9 * baseline + 0.1 * G;

            if strcmp(opts.mode, 'learned') && abs(adv) > 1e-12
                [Wop, bop] = linUpdate(Wop, bop, bufS(1,:), bufAo(1), p_op, adv, lr, opts);
                [Wlm, blm] = linUpdate(Wlm, blm, bufS(1,:), bufAl(1), p_lm, adv, lr, opts);
            end
            % shift the buffer down by one
            bufS(1:Wd-1, :) = bufS(2:Wd, :);
            bufAo(1:Wd-1) = bufAo(2:Wd); bufAl(1:Wd-1) = bufAl(2:Wd);
            bufR(1:Wd-1) = bufR(2:Wd);
            nBuf = Wd - 1;
        end

        if mod(ctr.nIter, 200) == 0
            curve(end+1) = bestKey(2); %#ok<AGROW>
            if opts.verbose
                fprintf('  %5.0fs it%6d  best %2d/%.1f  lam %.0f/%.0f  r=%.4f  b=%.3f\n', ...
                        ctr.elapsed(), ctr.nIter, bestKey(1), bestKey(2), ...
                        lam.cap, lam.tw, r, baseline);
            end
        end
    end

    if isempty(best)
        warning('solve_rlgbka_online:infeasible', 'no feasible solution found');
        best = x;
    end
    R = P.evalReport(best);

    served = [];
    for k = 1:numel(best), served = [served, best{k}(:).']; end %#ok<AGROW>
    if numel(served) ~= P.n || numel(unique(served)) ~= P.n
        warning('solve_rlgbka_online:incomplete', ...
                'solution serves %d (%d unique) of %d', numel(served), ...
                numel(unique(served)), P.n);
    end

    out = struct('dist', R.cost, 'nveh', R.nveh, 'feasible', R.feasible, ...
                 'iter', ctr.nIter, 'evals', ctr.nEval, 'secs', ctr.elapsed(), ...
                 'curve', curve, 'opUse', opUse, 'opSucc', opSucc, ...
                 'lamCap', lam.cap, 'lamTw', lam.tw, 'method', 'RLGBKA-Online', ...
                 'pool', {pool});
end


% ================================================================ helpers

function o = setdef(o, f, v)
    if ~isfield(o, f), o.(f) = v; end
end

function tf = lexBetter(a, b)
    if a(1) < b(1), tf = true; return; end
    tf = (a(1) == b(1)) && (a(2) < b(2) - 1e-9);
end

function a = sample(p)
    c = cumsum(p);
    a = find(rand <= c, 1, 'first');
    if isempty(a), a = numel(p); end
end

function [W, b] = linUpdate(W, b, s, a, p, adv, lr, opts)
%LINUPDATE  One REINFORCE step for a linear softmax policy.
    dz = -p; dz(a) = dz(a) + 1;
    if opts.entropy > 0
        pp = max(p, 1e-12);
        H = -sum(pp .* log(pp));
        dz = dz + opts.entropy * (-pp .* (log(pp) + H));
    end
    dz = dz * adv;
    gW = s' * dz;
    gb = dz;
    nrm = sqrt(sum(gW(:).^2) + sum(gb(:).^2));
    if nrm > opts.clip
        gW = gW * (opts.clip / nrm); gb = gb * (opts.clip / nrm);
    end
    W = W + lr * gW;
    b = b + lr * gb;
end

function s = buildState(fx, bestDist, scale, stagnation, win, Rx, P, ...
                        eliteKey, eliteDiv, recentSucc, recentUse)
    s = zeros(1, 24);
    s(1) = fx / scale;
    s(2) = bestDist / scale;
    s(3) = min(1, stagnation / max(win, 1));
    s(4) = Rx.nveh / max(P.m, 1);
    s(5) = min(1, Rx.capExcess / max(0.1 * sum(P.demand), 1e-9));
    s(6) = min(1, Rx.twExcess / max(P.due));
    s(7) = min(1, min(eliteKey(:, 2)) / scale);
    s(8) = min(1, eliteDiv);
    s(9:16)  = recentSucc ./ max(recentUse, 1);
    s(17:24) = recentUse / max(sum(recentUse), 1);
end

function p = succPairs(routes)
    p = zeros(0, 1);
    for r = 1:numel(routes)
        rt = routes{r};
        for k = 1:numel(rt)-1
            p(end+1, 1) = rt(k) * 100000 + rt(k+1); %#ok<AGROW>
        end
    end
end

function [elite, key] = pushElite(elite, key, cand, newKey, maxSize)
    for i = 1:size(key, 1)
        if lexBetter(newKey, key(i, :))
            elite = [{cand}, elite];
            key = [newKey; key];
            break;
        end
    end
    if numel(elite) > maxSize
        elite = elite(1:maxSize);
        key = key(1:maxSize, :);
    end
end

function d = diversityOf(elite, scale)
%DIVERSITYOF  Mean pairwise dissimilarity of the elite archive, normalised.
%
%   Computed every hundred iterations rather than every one: the archive changes
%   slowly, and the pairwise successor-set comparison is O(n) per member, which
%   as part of the per-iteration state dominated the loop.
    d = 0;
    if numel(elite) < 2, return; end
    acc = 0; cnt = 0;
    for i = 1:numel(elite)-1
        a1 = succPairs(elite{i}); a2 = succPairs(elite{i+1});
        if isempty(a1) || isempty(a2), continue; end
        acc = acc + (1 - numel(intersect(a1, a2)) / numel(union(a1, a2)));
        cnt = cnt + 1;
    end
    if cnt > 0, d = acc / cnt / max(scale, 1e-9); end
end
function tf = servesAll(routes, n)
%SERVESALL  True when the solution covers every customer exactly once.
%
%   NOTE ON CUSTOMER NUMBERING.  The instances number the depot as 1 and the
%   customers as 2..n+1, so a check written as "every id lies in 1..n" rejects
%   every correct solution.  The first version of this function did exactly that:
%   it marked all candidates incomplete, the search discarded all of them, and the
%   result was zero improvements over the constructive solution on every seed -- an
%   artefact that looked like a property of the algorithm.  Counting distinct
%   served ids is the check that does not depend on the numbering.
    total = 0;
    for r = 1:numel(routes)
        total = total + numel(routes{r});
    end
    if total ~= n, tf = false; return; end

    all = zeros(1, total);
    pos = 0;
    for r = 1:numel(routes)
        rt = routes{r};
        all(pos+1:pos+numel(rt)) = rt(:).';
        pos = pos + numel(rt);
    end
    tf = (numel(unique(all)) == n);
end
