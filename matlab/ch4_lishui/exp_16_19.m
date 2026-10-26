function exp_16_19()
% EXP_16_19  The remaining four experiments, after the battery sweep.
%
%   16  state of charge trace
%   17  window tightening
%   18  small instance against enumeration
%   19  convergence curves

F = 6; cap = 1200; budget = 20;
methods = {'CBLNS', 'ALNS', 'VNS', 'Tabu', 'GA'};
mname = {'proposed', 'ALNS', 'VNS', 'tabu', 'GA'};
col = [0.85 0.15 0.15; 0.15 0.35 0.85; 0.15 0.60 0.20; 0.70 0.40 0.10; 0.45 0.20 0.60];

%% ---------- 16  state of charge ----------
fprintf('\n===== 16  state of charge =====\n');
if isfile('exp1_best.mat')
    S = load('exp1_best.mat'); R = S.BEST.routes;
    C = case_load('cap', cap, 'windows', [12 17 19]);
    fig = figure('Position', [70 70 760 420], 'Color', 'w'); hold on
    hs = gobjects(numel(R), 1);
    for v = 1:numel(R)
        [t, soc] = soc_trace(C, R{v});
        hs(v) = plot(t, soc, '-', 'Color', col(mod(v-1,5)+1,:), 'LineWidth', 1.2);
        fprintf('vehicle %d: %d points, min %.1f kWh\n', v, numel(t), min(soc));
    end
    yline(C.SMIN, 'k--', 'LineWidth', 1.0);
    xlim([C.TSTART C.TEND]); ylim([0 C.B]);
    xlabel('hour'); ylabel('state of charge (kWh)'); grid on; box on
    legend(hs, arrayfun(@(v) sprintf('vehicle %d', v), 1:numel(R), 'UniformOutput', false), ...
        'Location', 'eastoutside', 'FontSize', 7);
    title('State of charge over the day, floor in dashed black', 'FontSize', 10);
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
    pts = randperm(200, 6) + 1;
    best = Inf;
    P = perms(pts);
    for k = 1:size(P,1)
        d = trip_dist(C, P(k,:));
        if d < best
            [ok, ~, ~, ~] = trip_eval(C, P(k,:), C.TSTART, C.B);
            if ok, best = d; end
        end
    end
    g = pts(1);
    for p = 2:numel(pts)
        bd = Inf; bp = 1;
        for pos = 1:numel(g)+1
            cand = [g(1:pos-1), pts(p), g(pos:end)];
            [ok, ~, ~, ~] = trip_eval(C, cand, C.TSTART, C.B);
            if ~ok, continue, end
            d = trip_dist(C, cand);
            if d < bd, bd = d; bp = pos; end
        end
        if isinf(bd), g = [g, pts(p)]; else, g = [g(1:bp-1), pts(p), g(bp:end)]; end
    end
    gd = trip_dist(C, g);
    if isfinite(best) && isfinite(gd)
        gaps(end+1) = (gd - best) / best * 100; %#ok<AGROW>
        fprintf('trial %2d  exact %7.2f  greedy %7.2f  gap %5.2f%%\n', trial, best, gd, gaps(end));
    end
end
fid = fopen('exp18_small.txt', 'w');
fprintf(fid, 'six points, one trip, twenty random subsets, full enumeration of 720 orders\n');
if ~isempty(gaps)
    fprintf(fid, 'trials %d, mean gap %.3f%%, max gap %.3f%%\n', numel(gaps), mean(gaps), max(gaps));
    fprintf('mean gap %.3f%%, max %.3f%%\n', mean(gaps), max(gaps));
end
fclose(fid);

%% ---------- 19  convergence ----------
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
end


function [t, soc] = soc_trace(C, tripList)
% replay one vehicle arc by arc, charging on demand exactly as route_eval does
[ok, ~, ~, ~, ~, dep, ~] = route_eval(C, tripList, C.TSTART, C.B);
t = []; soc = [];
if ~ok, return, end
s = C.B;
clock = C.TSTART;
for k = 1:numel(tripList)
    trip = tripList{k};
    load = 0;
    for j = 1:numel(trip), load = load + C.demand(trip(j)); end
    prev = 1;
    for j = 1:numel(trip)
        c = trip(j);
        [dt, e] = arc_cost(C, prev, c, clock, load);
        clock = clock + dt; s = s - e;
        load = max(0, load - C.demand(c));
        t(end+1) = clock; soc(end+1) = s; %#ok<AGROW>
        prev = c;
    end
    [dt, e] = arc_cost(C, prev, 1, clock, load);
    clock = clock + dt; s = s - e;
    t(end+1) = clock; soc(end+1) = s; %#ok<AGROW>
    if k < numel(tripList)
        clock = clock + C.LOADH;
        % the same rule route_eval uses: charge only what the next trip needs
        need = 0;
        nxt = tripList{k+1};
        if ~isempty(nxt)
            dl = 0; for j = 1:numel(nxt), dl = dl + C.demand(nxt(j)); end
            est = 0.0;
            prev = 1;
            for j = 1:numel(nxt)
                [~, e] = arc_cost(C, prev, nxt(j), clock, dl);
                est = est + e; dl = max(0, dl - C.demand(nxt(j))); prev = nxt(j);
            end
            [~, e] = arc_cost(C, prev, 1, clock, dl);
            est = est + e;
            need = max(0, min(C.B - s, C.SMIN + est - s));
        end
        if need > 0
            clock = clock + need / C.PCH;
            s = s + need;
            t(end+1) = clock; soc(end+1) = s; %#ok<AGROW>
        end
    end
end
end