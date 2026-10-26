function test_train()
%TEST_TRAIN  Smoke-test the REINFORCE loop on a tiny budget.
%
%   The point is to catch structural errors (field mismatches, gradient shape
%   problems, empty trajectories) before committing hours of CPU time.  It does
%   not try to show that the policy improves -- four episodes cannot show that.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    bdir = benchmark_dir();
    names = {'C1_2_1', 'R1_2_1'};
    Pset = {};
    for i = 1:numel(names)
        inst = read_vrptw_instance(fullfile(bdir, 'instances200', [names{i} '.TXT']));
        Pset{end+1} = problem_static(vrptw_model(inst)); %#ok<AGROW>
    end

    fprintf('training on %d instances\n', numel(Pset));

    opts = struct('episodes', 4, 'batch', 2, 'hidden', 16, ...
                  'budget', 3000, 'decideEvery', 10, ...
                  'lr', 1e-3, 'verbose', true);

    tic;
    [pol, hist] = train_rlgbka(Pset, opts);
    el = toc;

    fprintf('\ntrained in %.1f s over %d updates\n', el, numel(hist.ret));
    fprintf('returns   : %s\n', mat2str(round(hist.ret * 1e4) / 1e4));
    fprintf('entropy   : %s\n', mat2str(round(hist.ent * 1e3) / 1e3));
    if ~isempty(hist.opFreq)
        fprintf('action freq (last): %s\n', ...
                mat2str(round(hist.opFreq(end, :) * 100) / 100));
    end

    % the policy must still produce a valid forward pass
    s = rand(1, pol.d) * 0.5;
    [a, p, ~] = rlgbka_policy(pol, s, 'sample');
    fprintf('\nforward check: action %d, probs sum %.6f\n', a, sum(p));
    assert(abs(sum(p) - 1) < 1e-9, 'action probabilities must sum to one');
    assert(a >= 1 && a <= size(pol.W3, 2), 'sampled action out of range');
    fprintf('PASS\n');
end
