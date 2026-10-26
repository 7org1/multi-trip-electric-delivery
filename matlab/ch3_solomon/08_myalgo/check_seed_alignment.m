function check_seed_alignment()
%CHECK_SEED_ALIGNMENT  Are the five methods really run on the same seeds?
%
%   The comparison in compare_with_baselines pairs results by (instance, seed).  That
%   is only meaningful if every method has exactly one result for each of the five
%   seeds on every instance.  A missing seed, a duplicated seed or a run that was
%   re-executed after a crash would silently break the pairing and inflate whatever
%   p-value comes out.
%
%   This script checks, for each method and instance:
%       - the number of rows
%       - whether the seed set is exactly 1..5
%       - whether any seed appears twice
%   and then states plainly whether the pairing used in the comparison is valid.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    B = readtable(fullfile(here, '..', '09_solvers', 'results', 'all_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');
    M = readtable(fullfile(here, 'results12', 'merged_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');
    L = M(strcmp(M.mode, 'linucb-sched'), :);

    insts = unique(B.instance);
    methods = {'ALNS','VNS','Tabu','GA','LinUCB-sched'};
    want = (1:5).';

    fprintf('=== seed sets per (method, instance) ===\n');
    fprintf('%-14s %10s %10s %10s %10s\n', 'method', 'instances', 'all 5?', 'dups', 'totalRows');
    fprintf('%s\n', repmat('-', 1, 58));

    allOK = true;
    for k = 1:numel(methods)
        nBad = 0; nDup = 0; nRows = 0;
        for a = 1:numel(insts)
            if strcmp(methods{k}, 'LinUCB-sched')
                m = strcmp(L.instance, insts{a});
                s = L.seed(m);
            else
                m = strcmp(B.method, methods{k}) & strcmp(B.instance, insts{a});
                s = B.seed(m);
            end
            nRows = nRows + numel(s);
            if numel(s) ~= 5 || ~isequal(sort(s(:)), want)
                nBad = nBad + 1;
            end
            if numel(unique(s)) ~= numel(s)
                nDup = nDup + 1;
            end
        end
        fprintf('%-14s %10d %10s %10d %10d\n', methods{k}, numel(insts), ...
                ternary(nBad == 0, 'yes', sprintf('%d bad', nBad)), nDup, nRows);
        if nBad > 0 || nDup > 0, allOK = false; end
    end

    % ---- the pairing used by the comparison
    fprintf('\n=== pairing check: every (instance, seed) present in every method? ===\n');
    missing = 0;
    for a = 1:numel(insts)
        for s = want.'
            for k = 1:numel(methods)
                if strcmp(methods{k}, 'LinUCB-sched')
                    ok = any(strcmp(L.instance, insts{a}) & L.seed == s);
                else
                    ok = any(strcmp(B.method, methods{k}) & ...
                              strcmp(B.instance, insts{a}) & B.seed == s);
                end
                if ~ok
                    missing = missing + 1;
                    fprintf('  missing: %s %s seed %d\n', methods{k}, insts{a}, s);
                end
            end
        end
    end
    fprintf('  missing (instance, seed, method) combinations: %d\n', missing);

    % ---- what a seed actually controls
    fprintf('\n=== what the seed controls ===\n');
    fprintf('  every solver calls rng(opts.seed) at entry, so seed k fixes the initial\n');
    fprintf('  RNG state.  The five solvers then consume randomness differently --\n');
    fprintf('  different numbers of draws, different operators -- so seed k does NOT\n');
    fprintf('  give them a shared random stream.  The pairing controls the starting\n');
    fprintf('  point of the generator, not the trajectory.\n');

    if allOK && missing == 0
        fprintf('\nVERDICT: the pairing is valid -- five seeds, five methods, no gaps\n');
    else
        fprintf('\nVERDICT: the pairing is NOT valid, see the lines above\n');
    end
end


function o = ternary(c, a, b)
    if c, o = a; else, o = b; end
end
