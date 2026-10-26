function inspect_instance_structure()
%INSPECT_INSTANCE_STRUCTURE  Are the 10 instances inside one class actually
%different problems, or the same customers with different time windows?
%
% This matters for experimental design.  If the coordinates are shared, then
% the 10 instances in a class are 10 time-window assignments over ONE spatial
% layout, and reporting "average over 10 instances" is really "average over 10
% time-window settings" -- still valid, but it must be described correctly and
% it changes which instances are worth selecting.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    dir200 = fullfile(benchmark_dir(), 'instances200');

    classes = {'C1_2', 'C2_2', 'R1_2', 'R2_2', 'RC1_2', 'RC2_2'};

    fprintf('=== do instances within a class share coordinates? ===\n\n');
    for c = 1:numel(classes)
        base = read_vrptw_instance(fullfile(dir200, [classes{c} '_1.TXT']));
        sameCoord = true;
        twDiff = 0;
        nSame = 0;
        for j = 2:10
            p = fullfile(dir200, sprintf('%s_%d.TXT', classes{c}, j));
            if ~isfile(p), continue; end
            o = read_vrptw_instance(p);
            nSame = nSame + 1;
            if ~isequal(o.x, base.x) || ~isequal(o.y, base.y)
                sameCoord = false;
            end
            if ~isequal(o.ready, base.ready) || ~isequal(o.due, base.due)
                twDiff = twDiff + 1;
            end
        end
        fprintf('%-7s  coords identical: %-5s   instances with different time windows: %d / %d\n', ...
                classes{c}, ternary(sameCoord, 'YES', 'NO'), twDiff, nSame);
    end

    fprintf('\n=== depot and coordinate range per class ===\n\n');
    fprintf('%-7s %12s %10s %10s %10s\n', 'class', 'depot(x,y)', 'x-min', 'x-max', 'y-max');
    for c = 1:numel(classes)
        inst = read_vrptw_instance(fullfile(dir200, [classes{c} '_1.TXT']));
        fprintf('%-7s %12s %10g %10g %10g\n', classes{c}, ...
                sprintf('(%.0f,%.0f)', inst.x(1), inst.y(1)), ...
                min(inst.x), max(inst.x), max(inst.y));
    end

    fprintf('\n=== time-window width statistics (how tight are they?) ===\n\n');
    fprintf('%-7s %10s %10s %10s %12s\n', 'class', 'min width', 'median', 'max width', 'horizon');
    for c = 1:numel(classes)
        inst = read_vrptw_instance(fullfile(dir200, [classes{c} '_1.TXT']));
        w = inst.due - inst.ready;
        fprintf('%-7s %10g %10.0f %10g %12g\n', classes{c}, ...
                min(w(2:end)), median(w(2:end)), max(w(2:end)), max(inst.due));
    end

    fprintf('\n=== rounded-distance sanity check (depot -> customers) ===\n\n');
    inst = read_vrptw_instance(fullfile(dir200, 'C1_2_1.TXT'));
    D = distance_matrix(inst, 'round');
    fprintf('  C1_2_1 depot at (%.0f,%.0f)\n', inst.x(1), inst.y(1));
    fprintf('  nearest customer  distance : %g\n', min(D(1,2:end)));
    fprintf('  farthest customer distance : %g\n', max(D(1,2:end)));
    fprintf('  mean depot distance        : %.1f\n', mean(D(1,2:end)));
end


function s = ternary(c, a, b)
    if c, s = a; else, s = b; end
end
