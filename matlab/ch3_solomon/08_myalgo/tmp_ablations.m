function tmp_ablations()
% Which ablation comparisons does the saved data actually support?
%
%   Each pair below changes exactly one design decision, so the sign test on
%   vehicle counts is interpretable as an ablation rather than as an arbitrary
%   ranking.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    T = readtable(fullfile(here, 'results12', 'merged_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');

    pairs = {
        % label,                          A,                     B
        'Ablation 1  operators  S/W/R vs single',        'linucb_v3_standard', 'pure'
        'Ablation 2  dual-term normalisation',           'linucb',             'linucb_v3_standard'
        'Ablation 3  exploration alpha_t vs const',      'linucb',             'linucb-sched'
        'Ablation 4  reward scale x50',                  'linucb',             'linucb_v1_reward50'
        'Ablation 5  fast decay vs theory',              'linucb-sched',       'linucb_v2_fastdecay'
        'Ablation 6  thompson vs UCB',                   'linucb-sched',       'thompson'
        'Ablation 7  learning vs no learning',           'linucb_v3_standard', 'adaptive'
        'Ablation 8  stateless vs contextual',           'linucb_v3_standard', 'roundrobin'
    };

    fprintf('%-46s %7s %7s %6s %10s %10s\n', 'ablation', 'A win', 'B win', 'tie', 'sign p', 'meanDiff');
    fprintf('%s\n', repmat('-', 1, 92));
    for i = 1:size(pairs, 1)
        label = pairs{i, 1}; a = pairs{i, 2}; b = pairs{i, 3};
        ka = strcat(T.instance(strcmp(T.mode,a)), "_", string(T.seed(strcmp(T.mode,a))));
        va = T.veh(strcmp(T.mode,a));
        da = T.dist(strcmp(T.mode,a));
        kb = strcat(T.instance(strcmp(T.mode,b)), "_", string(T.seed(strcmp(T.mode,b))));
        vb = T.veh(strcmp(T.mode,b));
        db = T.dist(strcmp(T.mode,b));
        [~, ia, ib] = intersect(ka, kb);
        w = sum(va(ia) < vb(ib)); l = sum(va(ia) > vb(ib));
        t = sum(va(ia) == vb(ib));
        n = w + l;
        if n == 0
            p = 1;
        else
            k = min(w, l); tail = 0;
            for q = 0:k, tail = tail + nchoosek(n, q); end
            p = min(1, 2 * tail / 2^n);
        end
        fprintf('%-46s %7d %7d %6d %10.4f %+10.2f\n', label, w, l, t, p, ...
                mean(va(ia) - vb(ib)));
    end

    fprintf('\nfleet totals (sum over 12 instances of the mean over 5 seeds):\n');
    modes = unique(T.mode);
    for i = 1:numel(modes)
        m = strcmp(T.mode, modes{i});
        fprintf('  %-24s %8.2f   mean dist %8.1f\n', modes{i}, ...
                sum(T.veh(m))/5, mean(T.dist(m)));
    end
end
