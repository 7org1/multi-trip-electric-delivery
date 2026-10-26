function test_ops2()
%TEST_OPS2  Which of the four destroy operators actually helps on R1_2_1?
%
%   Each operator is run on its own, in a pure descent: a candidate is kept only
%   if it is feasible, serves every customer, and improves g = distance +
%   vehWeight*vehicles.  Isolating one operator at a time is the only way to tell
%   whether it contributes anything; mixed together, a dead operator is invisible.
%
%   R1_2_1 is the instance where the gap is largest (best known 20 / 4784.11,
%   everybody stalls at 22 vehicles), so an operator that does nothing here is not
%   going to do anything anywhere.
%
%   Reported per operator: time per call, number of accepted improvements, final
%   distance and vehicle count, and whether the fleet ever fell.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    addpath(fullfile(here, '..', '09_solvers'));

    bdir = benchmark_dir();
    inst = read_vrptw_instance(fullfile(bdir, 'instances200', 'R1_2_1.TXT'));
    S = vrptw_model(inst);
    P = problem_static(S);

    BKS_V = 20; BKS_D = 4784.11;
    VEHW = 1e4;
    SECS = 300;
    lam = struct('cap', 50, 'tw', 5);

    names = {'merge removal', 'worst removal', 'sector removal', 'large ruin'};

    fprintf('R1_2_1   construction: ');
    x0 = P.construct(); R0 = P.evalReport(x0);
    fprintf('%d / %.2f   (best known %d / %.2f)\n\n', R0.nveh, R0.cost, BKS_V, BKS_D);

    fprintf('%-15s %8s %10s %7s %10s %7s %8s\n', ...
            'operator', 'ms/call', 'calls', 'impr', 'dist', 'veh', 'gap%');
    fprintf('%s\n', repmat('-', 1, 72));

    res = zeros(4, 6);

    for id = 1:4
        rng(1);
        x = x0;
        Rx = P.evalReport(x);
        gcur = Rx.cost + VEHW * Rx.nveh;
        gbest = gcur; best = x; bestV = Rx.nveh; bestD = Rx.cost;
        ctr = cpu_budget(SECS);
        opts = struct('lam', lam, 'scale', 1);
        nImp = 0; nCall = 0; tOp = 0;

        while ~ctr.exhausted()
            t0 = cputime;
            [cand, aux] = rlgbka_ops2(id, P, x, opts);
            tOp = tOp + (cputime - t0);
            nCall = nCall + 1;
            ctr.tick();

            if aux.removed == 0 && ~aux.merged
                continue;
            end
            Rc = P.evalReport(cand);
            if ~Rc.feasible || ~servesAll(cand, P.n)
                continue;
            end
            gc = Rc.cost + VEHW * Rc.nveh;
            if gc < gcur - 1e-9
                x = cand; gcur = gc;
                nImp = nImp + 1;
                if gc < gbest - 1e-9
                    gbest = gc; best = cand; bestV = Rc.nveh; bestD = Rc.cost;
                end
            end
        end

        msPer = 1000 * tOp / max(nCall, 1);
        gap = 100 * (bestD - BKS_D) / BKS_D;
        fprintf('%-15s %8.1f %10d %7d %10.2f %7d %8.2f\n', ...
                names{id}, msPer, nCall, nImp, bestD, bestV, gap);
        res(id, :) = [msPer, nCall, nImp, bestD, bestV, gap];
    end

    fprintf('\nconstruction: %.2f at %d vehicles\n', R0.cost, R0.nveh);
    fprintf('ALNS reference: 4935.90 at 22 vehicles (3.17%%)\n');
end


function tf = servesAll(routes, n)
    total = 0;
    for r = 1:numel(routes), total = total + numel(routes{r}); end
    if total ~= n, tf = false; return; end
    all = zeros(1, total); pos = 0;
    for r = 1:numel(routes)
        rt = routes{r};
        all(pos+1:pos+numel(rt)) = rt(:).'; %#ok<AGROW>
        pos = pos + numel(rt);
    end
    tf = (numel(unique(all)) == n);
end
