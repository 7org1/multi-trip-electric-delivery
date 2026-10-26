function tmp_pure_vs()
% Which mixing modes does the single-operator control actually lose to?
%
%   The paper may want to state "a fixed single operator is significantly worse
%   than mixing", which requires the comparison against the configuration actually
%   used, not against an internal control that does not appear in the text.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    T = readtable(fullfile(here, 'results12', 'merged_per_seed.csv'), ...
                  'VariableNamingRule', 'preserve');

    modes = {'pure','roundrobin','adaptive','thompson','linucb', ...
             'linucb-sched','linucb_v1_reward50','linucb_v2_fastdecay', ...
             'linucb_v3_standard'};

    fprintf('%-46s %6s %6s %6s %10s %10s\n', 'pair', 'A win', 'B win', 'tie', 'sign p', 'meanDiff');
    fprintf('%s\n', repmat('-', 1, 92));
    for i = 1:numel(modes)
        for j = i+1:numel(modes)
            a = modes{i}; b = modes{j};
            if ~strcmp(a, 'pure'), continue; end
            ka = strcat(T.instance(strcmp(T.mode,a)), "_", string(T.seed(strcmp(T.mode,a))));
            va = T.veh(strcmp(T.mode,a));
            kb = strcat(T.instance(strcmp(T.mode,b)), "_", string(T.seed(strcmp(T.mode,b))));
            vb = T.veh(strcmp(T.mode,b));
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
            fprintf('%-46s %6d %6d %6d %10.4f %+10.2f\n', ...
                    [a ' vs ' b], w, l, t, p, mean(va(ia) - vb(ib)));
        end
    end
end
