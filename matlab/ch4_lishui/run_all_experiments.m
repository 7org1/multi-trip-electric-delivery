function run_all_experiments()
% RUN_ALL_EXPERIMENTS  Redo every experiment of Chapter 4 on the current instance.
%
%   One MATLAB process, one after another, so that the wall clock budget of every call
%   is not distorted by a competing job.  Each experiment writes its own csv and its
%   own summary, and nothing in the paper is touched.
%
%     exp1  five methods, five seeds, 20 s           the main comparison
%     exp3  the three regime figures and the table    from the logs of exp1
%     exp4  the route figure                          from the best solution of exp1
%     exp5  budget 5 10 20 40, five methods, 3 seeds  the anytime curve
%     exp6  fleet 5 6 7, three seeds                  why six vehicles
%     exp7  no charge constraint, five seeds          does the battery bind
%     exp8  constant speeds, five seeds               does time dependence matter
%     exp9  plan the day with constant speeds and run it under real speeds
%     exp10 gantt of the day                          multi-trip, charging, regimes
%
%   exp2, the ablation that removes the congestion features from the state, needs a
%   switch inside the solver and is run separately.

F = 6; cap = 1200; budget = 20;
methods = {'CBLNS', 'ALNS', 'VNS', 'Tabu', 'GA'};
tAll = tic;

%% ---------------- exp1  main comparison ----------------
fprintf('\n===== exp1  five methods, five seeds =====\n');
rows = {}; LOGS = {}; BEST = [];
for m = 1:numel(methods)
    for s = 1:5
        C = case_load('cap', cap, 'windows', [12 17 19]);
        t0 = tic; [R, o] = solve_day(C, F, methods{m}, budget, s); el = toc(t0);
        if isempty(o) || ~o.feasible, continue, end
        rows{end+1} = struct('method', methods{m}, 'seed', s, 'trips', o.trips, ...
            'distance', o.distance, 'obj', o.obj, 'iters', o.iters, 'seconds', el); %#ok<AGROW>
        if strcmp(methods{m}, 'CBLNS')
            LOGS{end+1} = o.log; %#ok<AGROW>
            if isempty(BEST) || o.obj < BEST.obj, BEST = o; BEST.routes = R; end
        end
        fprintf('%-6s seed %d  obj %7.1f  trips %2d  dist %7.1f  iters %4d  %.0fs\n', ...
            methods{m}, s, o.obj, o.trips, o.distance, o.iters, el);
    end
end
T1 = struct2table([rows{:}]); writetable(T1, 'exp1_main.csv');
write_summary(T1, methods, 'exp1', sprintf('five methods, fleet %d, capacity %d, budget %g s', F, cap, budget));
save('exp1_best.mat', 'BEST', '-v7');

%% ---------------- exp3  regime figures ----------------
fprintf('\n===== exp3  operator share by regime =====\n');
names = {'light', 'moderate', 'heavy'};
col = [0.85 0.15 0.15; 0.15 0.35 0.85; 0.15 0.60 0.20];
arms = {'sector', 'worst', 'random'};
tot = zeros(3,3);
for g = 1:3
    for s = 1:numel(LOGS), a = LOGS{s}(LOGS{s}(:,4) == g, 3); tot(g,:) = tot(g,:) + accumarray(a, 1, [3 1])'; end
end
fid = fopen('exp3_regime.csv', 'w');
fprintf(fid, 'regime,decisions,sector,worst,random\n');
for g = 1:3
    n = sum(tot(g,:));
    if n > 0
        fprintf(fid, '%s,%d,%.4f,%.4f,%.4f\n', names{g}, n, tot(g,1)/n, tot(g,2)/n, tot(g,3)/n);
        fprintf('%-9s %5d  sector %.3f  worst %.3f  random %.3f\n', names{g}, n, tot(g,1)/n, tot(g,2)/n, tot(g,3)/n);
    end
end
fclose(fid);
for g = 1:3
    fig = figure('Position', [80 80 700 430], 'Color', 'w'); hold on
    hs = gobjects(3,1); n = 0; Lm = inf;
    for s = 1:numel(LOGS)
        a = LOGS{s}(LOGS{s}(:,4) == g, 3);
        if isempty(a), continue, end
        n = n + numel(a); Lm = min(Lm, numel(a));
    end
    if isinf(Lm)
        for k = 1:3, hs(k) = plot(nan, nan, '-', 'Color', col(k,:), 'LineWidth', 1.6); end
    else
        for k = 1:3
            M = [];
            for s = 1:numel(LOGS)
                a = LOGS{s}(LOGS{s}(:,4) == g, 3);
                if numel(a) >= Lm, M(:, end+1) = cumsum(a(1:Lm) == k) ./ (1:Lm)'; end %#ok<AGROW>
            end
            hs(k) = plot(1:Lm, mean(M, 2), '-', 'Color', col(k,:), 'LineWidth', 1.8);
        end
        xlim([1 max(2, Lm)]);
    end
    ylim([0 1]); xlabel('decision within the regime'); ylabel('cumulative share');
    legend(hs, arms, 'Location', 'northeast'); grid on; box on
    title(sprintf('%s regime, %d decisions, %d seeds', names{g}, n, numel(LOGS)), 'FontSize', 11);
    print(fig, sprintf('fig_e_%s.png', names{g}), '-dpng', '-r260'); close(fig);
end
fprintf('regime figures written\n');

%% ---------------- exp4  route figure ----------------
fprintf('\n===== exp4  route figure =====\n');
C = case_load('cap', cap, 'windows', [12 17 19]);
plot_routes_grid(C, BEST.routes, 'fig_routes_grid.png', '');
fprintf('routes figure written\n');

%% ---------------- exp5  budget ----------------
fprintf('\n===== exp5  budget =====\n');
budgets = [5 10 20 40];
rows = {};
for b = budgets
    for m = 1:numel(methods)
        for s = 1:3
            C = case_load('cap', cap, 'windows', [12 17 19]);
            t0 = tic; [~, o] = solve_day(C, F, methods{m}, b, s); el = toc(t0);
            if isempty(o) || ~o.feasible, continue, end
            rows{end+1} = struct('method', methods{m}, 'budget', b, 'seed', s, 'obj', o.obj, ...
                'trips', o.trips, 'iters', o.iters, 'seconds', el); %#ok<AGROW>
            fprintf('%-6s budget %2d seed %d  obj %7.1f  iters %4d  %.0fs\n', methods{m}, b, s, o.obj, o.iters, el);
        end
    end
end
T5 = struct2table([rows{:}]); writetable(T5, 'exp5_budget.csv');
fid = fopen('exp5_budget_summary.txt', 'w');
fprintf(fid, '%-7s', 'budget'); for m = 1:numel(methods), fprintf(fid, '%12s', methods{m}); end; fprintf(fid, '\n');
for b = budgets
    fprintf(fid, '%-7d', b);
    for m = 1:numel(methods)
        sel = T5.budget == b & strcmp(T5.method, methods{m});
        if any(sel), fprintf(fid, '%12.1f', mean(T5.obj(sel))); else, fprintf(fid, '%12s', '-'); end
    end
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('budget sweep written\n');

%% ---------------- exp6  fleet ----------------
fprintf('\n===== exp6  fleet =====\n');
rows = {};
for Fv = [5 6 7]
    for s = 1:3
        C = case_load('cap', cap, 'windows', [12 17 19]);
        t0 = tic; [~, o] = solve_day(C, Fv, 'CBLNS', budget, s); el = toc(t0);
        if isempty(o) || ~o.feasible
            fprintf('fleet %d seed %d  infeasible  %.0fs\n', Fv, s, el);
            rows{end+1} = struct('fleet', Fv, 'seed', s, 'obj', NaN, 'trips', NaN, 'iters', 0, 'seconds', el); %#ok<AGROW>
            continue
        end
        rows{end+1} = struct('fleet', Fv, 'seed', s, 'obj', o.obj, 'trips', o.trips, ...
            'iters', o.iters, 'seconds', el); %#ok<AGROW>
        fprintf('fleet %d seed %d  obj %7.1f  trips %2d  iters %4d  %.0fs\n', Fv, s, o.obj, o.trips, o.iters, el);
    end
end
writetable(struct2table([rows{:}]), 'exp6_fleet.csv');
fprintf('fleet sweep written\n');

%% ---------------- exp7  no charge constraint ----------------
fprintf('\n===== exp7  no charge constraint =====\n');
rows = {};
for s = 1:5
    C = case_load('cap', cap, 'windows', [12 17 19]);
    C.B = 1e6; C.SMIN = 0;              % the battery never binds
    [~, o] = solve_day(C, F, 'CBLNS', budget, s);
    rows{end+1} = struct('seed', s, 'obj', o.obj, 'trips', o.trips, 'distance', o.distance, 'iters', o.iters); %#ok<AGROW>
    fprintf('seed %d  obj %7.1f  trips %2d  dist %7.1f\n', s, o.obj, o.trips, o.distance);
end
writetable(struct2table([rows{:}]), 'exp7_nocharge.csv');
fprintf('no charge experiment written\n');

%% ---------------- exp8  constant speeds ----------------
fprintf('\n===== exp8  constant speeds =====\n');
rows = {};
for s = 1:5
    C = case_load('cap', cap, 'windows', [12 17 19]);
    C.Tall = repmat(C.Tall(6, :, :), 9, 1, 1);   % the daily mean band in every band
    [~, o] = solve_day(C, F, 'CBLNS', budget, s);
    rows{end+1} = struct('seed', s, 'obj', o.obj, 'trips', o.trips, 'distance', o.distance, 'iters', o.iters); %#ok<AGROW>
    fprintf('seed %d  obj %7.1f  trips %2d  dist %7.1f\n', s, o.obj, o.trips, o.distance);
end
writetable(struct2table([rows{:}]), 'exp8_constspeed.csv');
fprintf('constant speed experiment written\n');

%% ---------------- exp9  plan static, run dynamic ----------------
fprintf('\n===== exp9  static plan, dynamic execution =====\n');
rows = {};
for s = 1:5
    C = case_load('cap', cap, 'windows', [12 17 19]);
    Treal = C.Tall;
    C.Tall = repmat(C.Tall(6, :, :), 9, 1, 1);
    [R, oS] = solve_day(C, F, 'CBLNS', budget, s);
    C.Tall = Treal;
    badTrip = 0; lateTrip = 0; lateMin = 0; tot_trip = 0;
    for v = 1:numel(R)
        [ok, ~, ~, ~, ~, dep, ret] = route_eval(C, R{v}, C.TSTART, C.B);
        tot_trip = tot_trip + numel(R{v});
        if ~ok
            badTrip = badTrip + 1;
        end
        if numel(dep) == numel(ret)
            for k = 1:numel(ret)
                if ret(k) > C.TEND - 1e-9, lateTrip = lateTrip + 1; lateMin = lateMin + (ret(k) - C.TEND) * 60; end
            end
        end
    end
    rows{end+1} = struct('seed', s, 'staticObj', oS.obj, 'routes', numel(R), ...
        'trips', tot_trip, 'badRoutes', badTrip, 'lateTrips', lateTrip, 'lateMin', lateMin); %#ok<AGROW>
    fprintf('seed %d  static obj %.1f  routes %d  trips %d  infeasible routes %d  late trips %d\n', ...
        s, oS.obj, numel(R), tot_trip, badTrip, lateTrip);
end
writetable(struct2table([rows{:}]), 'exp9_static_plan.csv');
fprintf('static plan experiment written\n');

%% ---------------- exp10  gantt ----------------
fprintf('\n===== exp10  gantt =====\n');
C = case_load('cap', cap, 'windows', [12 17 19]);
plot_gantt(C, BEST.routes, 'fig_gantt.png');
fprintf('gantt written\n');

fprintf('\nall experiments done in %.0f minutes\n', toc(tAll)/60);
end


function write_summary(T, methods, tag, subtitle)
fid = fopen([tag '_summary.txt'], 'w');
fprintf(fid, '%s\n\n', subtitle);
fprintf(fid, '%-7s %7s %10s %10s %9s %9s %8s %8s\n', 'method', 'trips', 'dist', 'dist_sd', 'obj', 'obj_sd', 'best', 'worst');
for m = 1:numel(methods)
    sel = strcmp(T.method, methods{m});
    if ~any(sel), continue, end
    fprintf(fid, '%-7s %7.2f %10.1f %10.1f %9.1f %9.1f %8.1f %8.1f\n', methods{m}, ...
        mean(T.trips(sel)), mean(T.distance(sel)), std(T.distance(sel)), ...
        mean(T.obj(sel)), std(T.obj(sel)), min(T.obj(sel)), max(T.obj(sel)));
end
fclose(fid);
fprintf('wrote %s_summary.txt\n', tag);
end
