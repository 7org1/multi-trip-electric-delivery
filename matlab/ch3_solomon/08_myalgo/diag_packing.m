function diag_packing()
%DIAG_PACKING  Why does the solver miss the best-known fleet count?
%
%   Two very different failures look identical in the results table:
%
%     (a) CAPACITY PACKING  -- the customers simply do not fit into the target
%         number of bins at the given capacity.  This is bin packing, and the
%         fix is a packing-aware construction, not a better local search.
%
%     (b) TIME WINDOWS      -- capacity is fine but the routes cannot be
%         sequenced to meet the windows.  The fix is a sequencing operator.
%
%   This test separates them: pack purely by demand with first-fit-decreasing,
%   ignoring time windows, and count the bins.  If that already needs more bins
%   than the best known uses, the barrier is capacity.  If it packs into fewer
%   bins, the barrier is sequencing.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', '07_benchmark_tools'));

    bdir = benchmark_dir();
    names = {'C1_2_1','C2_2_1','R1_2_1','R2_2_1','RC1_2_1','RC2_2_1'};
    b.k = load_bks(fullfile(bdir, 'gh200_bks.csv'));

    fprintf('%-9s %5s %7s %8s %9s %9s %9s\n', ...
            'instance', 'Q', 'demand', 'capLB', 'FFD bins', 'bksVeh', 'note');
    fprintf('%s\n', repmat('-', 1, 66));

    for i = 1:numel(names)
        inst = read_vrptw_instance(fullfile(bdir, 'instances200', [names{i} '.TXT']));
        % pack customers 1..n (index 1 of the array is the depot)
        dem = inst.demand(2:end);
        Q = inst.Q;

        capLB = ceil(sum(dem) / Q);
        bins = ffd(dem, Q);

        key = matlab.lang.makeValidName(lower(inst.name));
        bk = b.k.(key).routes;

        note = '';
        if bins > bk
            note = 'CAPACITY is the barrier';
        elseif capLB > bk
            note = 'inconsistent (capLB > bks)';
        else
            note = 'capacity fine -> TIME WINDOWS';
        end

        fprintf('%-9s %5g %7g %8d %9d %9d %9s\n', ...
                lower(inst.name), Q, sum(dem), capLB, bins, bk, note);
    end
end

function n = ffd(dem, Q)
%FFD  First-fit decreasing bin packing; returns the number of bins used.
    d = sort(dem, 'descend');
    loads = [];
    for i = 1:numel(d)
        placed = false;
        for b = 1:numel(loads)
            if loads(b) + d(i) <= Q + 1e-9
                loads(b) = loads(b) + d(i);
                placed = true;
                break;
            end
        end
        if ~placed
            loads(end+1) = d(i); %#ok<AGROW>
        end
    end
    n = numel(loads);
end
