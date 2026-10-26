function exp_15_19()
% EXP_15_19  The five experiments that remain after the main suite.
%
%   15  battery capacity sensitivity      when does the charge start to bind
%   16  state of charge trace             a picture of the battery over the day
%   17  window tightening                 does a tighter instance separate the methods
%   18  small instance against enumeration is the trip order optimal
%   19  convergence curves                best objective against the iteration
%
%   Everything is written to its own csv or png.  Nothing in the paper is touched.

F = 6; cap = 1200; budget = 20;
methods = {'CBLNS', 'ALNS', 'VNS', 'Tabu', 'GA'};
mname = {'proposed', 'ALNS', 'VNS', 'tabu', 'GA'};
col = [0.85 0.15 0.15; 0.15 0.35 0.85; 0.15 0.60 0.20; 0.70 0.40 0.10; 0.45 0.20 0.60];
tAll = tic;

%% ---------- 15  battery capacity ----------
fprintf('\n===== 15  battery capacity =====\n');
rows = {};
for Bv = [20 25 30 40]
    for s = 1:5
        C = case_load('cap', cap, 'windows', [12 17 19]);
        C.B = Bv; C.SMIN = 0.2 * Bv;
        [~, o] = solve_day(C, F, 'CBLNS', budget, s);
        if isempty(o) || ~o.feasible
            fprintf('B=%2d seed %d  infeasible\n', Bv, s);
            rows{end+1} = struct('B', Bv, 'seed', s, 'obj', NaN, 'trips', NaN, 'distance', NaN); %#ok<AGROW>
            continue
        end
        rows{end+1} = struct('B', Bv, 'seed', s, 'obj', o.obj, 'trips', o.trips, 'distance', o.distance); %#ok<AGROW>
        fprintf('B=%2d seed %d  obj %7.1f  trips %2d  dist %7.1f\n', Bv, s, o.obj, o.trips, o.distance);
    end
end
T15 = struct2table([rows{:}]); writetable(T15, 'exp15_battery.csv');
Bs = [20 25 30 40];
mu = nan(1,4); tr = nan(1,4);
for b = 1:4
    sel = T15.B == Bs(b) & ~isnan(T15.obj);
    if any(sel), mu(b) = mean(T15.obj(sel)); tr(b) = mean(T15.trips(sel)); end
end
fig = figure('Position', [70 70 620 400], 'Color', 'w');
yyaxis left; plot(Bs, mu, '-o', 'LineWidth', 1.6, 'MarkerFaceColor', 'auto'); ylabel('mean objective');
yyaxis right; plot(Bs, tr, '-s', 'LineWidth', 1.4); ylabel('mean trips');
xlabel('battery capacity (kWh)'); grid on; box on
title('Where the charge begins to bind', 'FontSize', 10);
print(fig, 'fig_f6_battery.png', '-dpng', '-r260'); close(fig);
fprintf('wrote fig_f6_battery.png\n');

%% ---------- 16  state of charge trace ----------
fprintf('\n===== 16  state of charge =====\n');
if isfile('exp1_best.mat')
    S = load('exp1_best.mat'); R = S.BEST.routes;
    C = case_load('cap', cap, 'windows', [12 17 19]);
    fig = figure('Position', [70 70 760 420], 'Color', 'w'); hold on
    hs = gobjects(numel(R), 1);
    for v = 1:numel(R)
        [t, soc] = soc_trace(C, R{v});
        hs(v) = plot(t, soc, '-', 'Color', col(mod(v-1,5)+1,:), 'LineWidth', 1.2);
    end
    yline(C.SMIN, 'k--', 'LineWidth', 1.0);
    text(C.TSTART+0.1, C.SMIN+0.4, 'floor', 'FontSize', 7);
    xlim([C.TSTART C.TEND]); ylim([0 C.B]);
    xlabel('hour'); ylabel('state of charge (kWh)'); grid on; box on
    legend(hs, arrayfun(@(v) sprintf('vehicle %d', v), 1:numel(R), 'UniformOutput', false), ...
        'Location', 'eastoutside', 'FontSize', 7);
    title('State of charge over the day', 'FontSize', 10);
    print(fig, 'fig_f7_soc.png', '-dpng', '-r260'); close(fig);
    fprintf('wrote fig_f7_soc.png\n');
end

%% ---------- 17  window tightening ----------
fprintf('\n===== 17  window tightening =====\n');
rows = {};
sets = {[12 17 19], [11 16 18], [10 15 17]};
sname = {'12/17/19', '11/16/18', '10/15/17'};
for w = 1:numel(sets)
    for m = 1:numel(methods)
        for s = 1:3
            C = case_load('cap', cap, 'windows', sets{w});
            [~, o] = solve_day(C, F, methods{m}, budget, s);
            if isempty(o) || ~o.feasible
                fprintf('%-8s %-6s seed %d  infeasible\n', sname{w}, methods{m}, s);
                rows{end+1} = struct('windows', sname{w}, 'method', methods{m}, 'seed', s, ...
                    'obj', NaN, 'trips', NaN, 'distance', NaN); %#ok<AGROW>
                continue
            end
            rows{end+1} = struct('windows', sname{w}, 'method', methods{m}, 'seed', s, ...
                'obj', o.obj, 'trips', o.trips, 'distance', o.distance); %#ok<AGROW>
            fprintf('%-8s %-6s seed %d  obj %7.1f  trips %2d  dist %7.1f\n', ...
                sname{w}, methods{m}, s, o.obj, o.trips, o.distance);
        end
    end
end
T17 = struct2table([rows{:}]); writetable(T17, 'exp17_windows.csv');
fid = fopen('exp17_windows_summary.txt', 'w');
fprintf(fid, '%-9s %-8s %8s %8s %8s\n', 'windows', 'method', 'obj', 'trips', 'dist');
for w = 1:numel(sets)
    for m = 1:numel(methods)
        sel = strcmp(T17.windows, sname{w}) & strcmp(T17.method, methods{m}) & ~isnan(T17.obj);
        if any(sel)
            fprintf(fid, '%-9s %-8s %8.1f %8.2f %8.1f\n', sname{w}, methods{m}, ...
                mean(T17.obj(sel)), mean(T17.trips(sel)), mean(T17.distance(sel)));
        end
    end
end
fclose(fid);
fprintf('window sweep written\n');

%% ---------- 18  small instance against enumeration ----------
fprintf('\n===== 18  trip order against enumeration =====\n');
C = case_load('cap', cap, 'windows', [12 17 19]);
rng(7);
gaps = [];
for trial = 1:20
    pts = randperm(200, 7) + 1;
    best = Inf;
    P = perms(pts);
    for k = 1:size(P,1)
        d = trip_dist(C, P(k,:));
        if d < best
            [ok, ~, ~, ~] = trip_eval(C, P(k,:), C.TSTART, C.B);
            if ok, best = d; end
        end
    end
    % greedy insertion
    g = [pts(1)];
    for p = 2:numel(pts)
        bd = Inf; bp = 1;
        for pos = 1:numel(g)+1
            cand = [g(1:pos-1), pts(p), g(pos:end)];
            [ok, ~, ~, ~] = trip_eval(C, cand, C.TSTART, C.B);
            if ~ok, continue, end
            d = trip_dist(C, cand);
            if d < bd, bd = d; bp = pos; end
        end
        if isinf(bd)
            g = [g, pts(p)];
        else
            g = [g(1:bp-1), pts(p), g(bp:end)];
        end
    end
    gd = trip_dist(C, g);
    if isfinite(best) && isfinite(gd)
        gaps(end+1) = (gd - best) / best * 100; %#ok<AGROW>
        fprintf('trial %2d  exact %7.2f  greedy %7.2f  gap %5.2f%%\n', trial, best, gd, gaps(end));
    end
end
fid = fopen('exp18_small.txt', 'w');
fprintf(fid, 'seven points, one trip, twenty random subsets\n');
fprintf(fid, 'trials %d, mean gap %.3f%%, max gap %.3f%%\n', numel(gaps), mean(gaps), max(gaps));
fclose(fid);
fprintf('mean gap %.3f%%, max %.3f%%\n', mean(gaps), max(gaps));

%% ---------- 19  convergence curves ----------
fprintf('\n===== 19  convergence =====\n');
fig = figure('Position', [70 70 660 420], 'Color', 'w'); hold on
hs = gobjects(numel(methods), 1);
for m = 1:numel(methods)
    curves = {};
    for s = 1:3
        C = case_load('cap', cap, 'windows', [12 17 19]);
        [~, o] = solve_day(C, F, methods{m}, budget, s);
        if isfield(o, 'log') && size(o.log, 2) >= 5
            curves{end+1} = o.log(:,5)'; %#ok<AGROW>
        end
        fprintf('%-6s seed %d  obj %.1f  iters %d\n', methods{m}, s, o.obj, o.iters);
    end
    if isempty(curves), continue, end
    n = min(cellfun(@numel, curves));
    M = zeros(numel(curves), n);
    for kk = 1:numel(curves), M(kk,:) = curves{kk}(1:n); end
    hs(m) = plot(1:n, mean(M, 1), '-', 'Color', col(m,:), 'LineWidth', 1.5);
end
xlabel('iteration'); ylabel('best objective'); grid on; box on
legend(hs, mname, 'Location', 'northeast');
title('Best objective against the iteration', 'FontSize', 10);
print(fig, 'fig_f8_convergence.png', '-dpng', '-r260'); close(fig);
fprintf('wrote fig_f8_convergence.png\n');

fprintf('\nall five done in %.0f minutes\n', toc(tAll)/60);
end


function [t, soc] = soc_trace(C, tripList)
% charge and time at the end of every trip of one vehicle, read from route_eval
[ok, ~, ~, ~, socEnd, dep, ret] = route_eval(C, tripList, C.TSTART, C.B);
t = []; soc = [];
if ~ok, return, end
for k = 1:numel(ret)
    t(end+1) = dep(k);   soc(end+1) = NaN;   %#ok<AGROW>
    t(end+1) = ret(k);   soc(end+1) = socEnd(k); %#ok<AGROW>
    if k < numel(ret) && dep(k+1) > ret(k)
        t(end+1) = dep(k+1); soc(end+1) = socEnd(k); %#ok<AGROW>
    end
end
if numel(t) >= 2
    v = soc(2:end);
    v = v(~isnan(v));
    if ~isempty(v)
        soc(1) = v(1);
    end
end
soc = fillmissing(soc, 'previous');
soc(isnan(soc)) = C.B;
end
