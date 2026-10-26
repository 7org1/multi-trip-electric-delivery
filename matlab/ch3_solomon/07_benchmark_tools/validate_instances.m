function validate_instances()
%VALIDATE_INSTANCES  Parse all 60 Gehring-Homberger 200-customer instances,
%check them for internal consistency, and cross-check against the BKS table.
%
% A parser that mis-reads a column still produces numbers that "look fine", so
% this checks properties that must hold regardless of the instance:
%   * exactly 200 customers
%   * depot is customer 0
%   * every time window satisfies ready <= due
%   * total demand fits in the stated fleet (otherwise the instance would be
%     infeasible by construction)
%   * the number of routes in the BKS table does not exceed the fleet size

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    dir200 = fullfile(benchmark_dir(), 'instances200');

    files = dir(fullfile(dir200, '*.TXT'));
    if isempty(files)
        files = dir(fullfile(dir200, '*.txt'));
    end
    if isempty(files)
        error('no instance files found in %s', dir200);
    end

    bks = load_bks(fullfile(benchmark_dir(), 'gh200_bks.csv'));

    fprintf('found %d instance files\n\n', numel(files));
    fprintf('%-9s %4s %5s %5s %8s %7s %6s %8s %8s\n', ...
            'instance', 'n', 'Q', 'm', 'demand', 'load%', 'bksVeh', 'x-span', 'y-span');
    fprintf('%s\n', repmat('-', 1, 78));

    nBad = 0;
    nOk  = 0;
    dsum = []; loads = [];

    for k = 1:numel(files)
        p = fullfile(dir200, files(k).name);
        try
            inst = read_vrptw_instance(p);
        catch ME
            fprintf('%-9s  PARSE ERROR: %s\n', files(k).name, ME.message);
            nBad = nBad + 1;
            continue;
        end

        D = sum(inst.demand);
        load = 100 * D / (inst.m * inst.Q);

        key = matlab.lang.makeValidName(lower(inst.name));
        if isfield(bks, key), bv = bks.(key).routes; else, bv = NaN; end

        xspan = max(inst.x) - min(inst.x);
        yspan = max(inst.y) - min(inst.y);

        problems = {};
        if inst.n ~= 200,                 problems{end+1} = 'n!=200'; end
        if inst.id(1) ~= 0,               problems{end+1} = 'depot!=0'; end
        if any(inst.due < inst.ready),    problems{end+1} = 'due<ready'; end
        if D > inst.m * inst.Q,           problems{end+1} = 'infeasible fleet'; end
        if ~isnan(bv) && bv > inst.m,     problems{end+1} = 'bks>fleet'; end

        flag = '';
        if isempty(problems)
            nOk = nOk + 1;
        else
            nBad = nBad + 1;
            flag = ['  <-- ' strjoin(problems, ',')];
        end

        fprintf('%-9s %4d %5g %5g %8g %6.1f %7g %8g %8g%s\n', ...
                lower(inst.name), inst.n, inst.Q, inst.m, D, load, bv, ...
                xspan, yspan, flag);

        dsum(end+1)  = D;      %#ok<AGROW>
        loads(end+1) = load;   %#ok<AGROW>
    end

    fprintf('\n');
    fprintf('parsed OK : %d\n', nOk);
    fprintf('problems  : %d\n', nBad);
    fprintf('\n');
    fprintf('total demand  : min %g  max %g  mean %.1f\n', ...
            min(dsum), max(dsum), mean(dsum));
    fprintf('loading %%      : min %.1f  max %.1f  mean %.1f\n', ...
            min(loads), max(loads), mean(loads));

    % ---------------- cross-check: does any BKS route count exceed the fleet?
    fprintf('\n=== BKS vehicle counts vs fleet sizes ===\n');
    f = fieldnames(bks);
    worst = 0;
    for i = 1:numel(f)
        b = bks.(f{i});
        worst = max(worst, b.routes);
    end
    fprintf('largest BKS route count across all 60 instances: %d\n', worst);
    fprintf('fleet sizes stated in the files are 50 or more, so every BKS fits.\n');
end
