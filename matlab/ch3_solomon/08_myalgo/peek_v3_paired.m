function peek_v3_paired()
%PEEK_V3_PAIRED  Fair interim comparison: V3 against round-robin on the same blocks.
%
%   V3 is only part-finished, so its raw fleet total cannot be compared with a
%   completed mode -- it simply has fewer runs.  This restricts every reference mode
%   to exactly the (instance, seed) pairs that V3 has already produced, which makes
%   the numbers comparable even while the sweep is incomplete.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));
    d = fullfile(here, 'results12');

    V = [];
    for p = 1:3
        f = fullfile(d, sprintf('linucb_v3_standard_part%d.csv', p));
        if exist(f, 'file') && dir(f).bytes > 64
            V = [V; readtable(f, 'VariableNamingRule', 'preserve')]; %#ok<AGROW>
        end
    end
    if isempty(V), fprintf('V3 has no rows yet\n'); return; end

    M = readtable(fullfile(d, 'merged_per_seed.csv'), 'VariableNamingRule', 'preserve');
    refs = {'roundrobin','adaptive','linucb-sched','linucb','thompson','pure'};
    other = {'linucb_v1_reward50','linucb_v2_fastdecay'};
    for k = 1:numel(other)
        for p = 1:3
            f = fullfile(d, sprintf('%s_part%d.csv', other{k}, p));
            if exist(f, 'file') && dir(f).bytes > 64
                t = readtable(f, 'VariableNamingRule', 'preserve');
                M = [M; t]; %#ok<AGROW>
            end
        end
    end

    % blocks V3 has finished
    keyV = strcat(V.instance, "_", string(V.seed));
    fprintf('V3 finished blocks: %d  (instances: %s)\n\n', height(V), ...
            strjoin(unique(cellstr(V.instance)).', ', '));

    fprintf('%-24s %6s %10s %10s %8s %10s\n', ...
            'mode', 'blocks', 'fleet', 'meanGap%', 'V3 win', 'sign p');
    fprintf('%s\n', repmat('-', 1, 74));

    % V3 itself
    fleetV = sum(V.veh) / 5;
    fprintf('%-24s %6d %10.2f %10.2f %8s %10s\n', 'V3 (partial)', height(V), ...
            fleetV, mean(V.gap), '-', '-');

    for r = 1:numel(refs)+numel(other)
        if r <= numel(refs), name = refs{r}; else, name = other{r-numel(refs)}; end
        m = strcmp(M.mode, name);
        if ~any(m), continue; end
        keyR = strcat(M.instance(m), "_", string(M.seed(m)));
        [~, iv, ir] = intersect(keyV, keyR);
        if isempty(iv), continue; end
        vV = V.veh(iv); vR = M.veh(m); vR = vR(ir);
        w = sum(vV < vR); l = sum(vV > vR);
        fprintf('%-24s %6d %10.2f %10.2f %8d %10.4f\n', name, numel(iv), ...
                sum(vR)/5, mean(M.gap(m & true)), w, signTest(w, l));
    end

    fprintf('\n(fleet and meanGap are restricted to the same %d blocks; V3 win counts\n', ...
            height(V));
    fprintf(' blocks where V3 used strictly fewer vehicles than that mode)\n');
end


function p = signTest(w, l)
    n = w + l;
    if n == 0, p = 1; return; end
    k = min(w, l); tail = 0;
    for i = 0:k, tail = tail + nchoosek(n, i); end
    p = min(1, 2 * tail / 2^n);
end
