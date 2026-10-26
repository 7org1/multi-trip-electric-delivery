function plot_all_figures()
% PLOT_ALL_FIGURES  Turn the experiment csv files into the figures of Chapter 4.
%
%   Reads whatever the experiment suite produced and draws one figure per question, so
%   that the chapter carries pictures rather than only tables.  A figure is skipped
%   when its csv is missing, so this can be run at any time.

col = [0.85 0.15 0.15; 0.15 0.35 0.85; 0.15 0.60 0.20; 0.70 0.40 0.10; 0.45 0.20 0.60];
methods = {'CBLNS', 'ALNS', 'VNS', 'Tabu', 'GA'};
mname = {'proposed', 'ALNS', 'VNS', 'tabu', 'GA'};

%% F1  objective against budget
if isfile('exp5_budget.csv')
    T = readtable('exp5_budget.csv');
    budgets = unique(T.budget)';
    fig = figure('Position', [70 70 620 420], 'Color', 'w'); hold on
    hs = gobjects(numel(methods),1);
    for m = 1:numel(methods)
        mu = nan(1, numel(budgets)); sd = mu;
        for b = 1:numel(budgets)
            sel = T.budget == budgets(b) & strcmp(T.method, methods{m});
            if any(sel), mu(b) = mean(T.obj(sel)); sd(b) = std(T.obj(sel)); end
        end
        errorbar(budgets, mu, sd, '-o', 'Color', col(m,:), 'LineWidth', 1.4, ...
            'MarkerFaceColor', col(m,:), 'MarkerSize', 4, 'CapSize', 4);
        hs(m) = plot(nan, nan, '-o', 'Color', col(m,:), 'LineWidth', 1.4);
    end
    set(gca, 'XScale', 'log');
    xlabel('CPU budget (s)'); ylabel('objective'); grid on; box on
    legend(hs, mname, 'Location', 'northeast'); 
    title('Objective against the budget', 'FontSize', 10);
    print(fig, 'fig_f1_budget.png', '-dpng', '-r260'); close(fig);
    fprintf('wrote fig_f1_budget.png\n');
end

%% F2  fleet size
if isfile('exp6_fleet.csv')
    T = readtable('exp6_fleet.csv');
    fleets = unique(T.fleet)';
    mu = nan(1, numel(fleets)); tr = mu; ok = false(1, numel(fleets));
    for f = 1:numel(fleets)
        sel = T.fleet == fleets(f) & ~isnan(T.obj);
        if any(sel), mu(f) = mean(T.obj(sel)); tr(f) = mean(T.trips(sel)); ok(f) = true; end
    end
    fig = figure('Position', [70 70 560 400], 'Color', 'w');
    bar(mu, 'FaceColor', [0.35 0.55 0.80]); hold on
    for f = 1:numel(fleets)
        if ~ok(f), text(f, max(mu(~isnan(mu)))*0.5, 'infeasible', 'HorizontalAlignment', 'center', 'FontSize', 8); end
        if ok(f), text(f, mu(f)*0.97, sprintf('%.0f trips', tr(f)), 'HorizontalAlignment', 'center', 'FontSize', 8, 'Color', 'w'); end
    end
    set(gca, 'XTick', 1:numel(fleets), 'XTickLabel', arrayfun(@(x) sprintf('%d', x), fleets, 'UniformOutput', false));
    xlabel('fleet size'); ylabel('mean objective'); grid on; box on
    title('Objective against the fleet size', 'FontSize', 10);
    print(fig, 'fig_f2_fleet.png', '-dpng', '-r260'); close(fig);
    fprintf('wrote fig_f2_fleet.png\n');
end

%% F3 and F4  constraint ablations, against the full model
base = NaN;
if isfile('exp1_main.csv')
    T1 = readtable('exp1_main.csv');
    base = mean(T1.obj(strcmp(T1.method, 'CBLNS')));
end
groups = {};
vals = [];
if isfile('exp7_nocharge.csv') && ~isnan(base)
    T = readtable('exp7_nocharge.csv');
    groups{end+1} = 'no charge constraint'; vals(end+1) = mean(T.obj);
end
if isfile('exp8_constspeed.csv') && ~isnan(base)
    T = readtable('exp8_constspeed.csv');
    groups{end+1} = 'constant speeds'; vals(end+1) = mean(T.obj);
end
if ~isempty(vals)
    fig = figure('Position', [70 70 620 400], 'Color', 'w'); hold on
    allv = [base vals]; alln = [{'full model'} groups];
    b = bar(allv);
    b.FaceColor = 'flat';
    b.CData = [0.25 0.45 0.70];
    for k = 1:numel(allv), text(k, allv(k)*0.985, sprintf('%.1f', allv(k)), 'HorizontalAlignment', 'center', 'FontSize', 8, 'Color', 'w'); end
    set(gca, 'XTick', 1:numel(allv), 'XTickLabel', alln);
    ylabel('mean objective'); grid on; box on
    ylim([min(allv)*0.96 max(allv)*1.02]);
    title('What the constraints cost', 'FontSize', 10);
    print(fig, 'fig_f3_ablation.png', '-dpng', '-r260'); close(fig);
    fprintf('wrote fig_f3_ablation.png\n');
end

%% F5  static plan run under real speeds
if isfile('exp9_static_plan.csv')
    T = readtable('exp9_static_plan.csv');
    fig = figure('Position', [70 70 620 400], 'Color', 'w');
    b = bar([mean(T.badRoutes) mean(T.lateTrips)]);
    b.FaceColor = 'flat'; b.CData = [0.80 0.35 0.25];
    text(1, mean(T.badRoutes), sprintf('%.1f', mean(T.badRoutes)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 9);
    text(2, mean(T.lateTrips), sprintf('%.1f', mean(T.lateTrips)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 9);
    set(gca, 'XTick', 1:2, 'XTickLabel', {'routes infeasible', 'trips late'});
    grid on; box on
    title('A plan built on mean speeds, then driven at the real speeds', 'FontSize', 10);
    print(fig, 'fig_f4_static_plan.png', '-dpng', '-r260'); close(fig);
    fprintf('wrote fig_f4_static_plan.png\n');
end

%% F6  objective by method, as a box plot
if isfile('exp1_main.csv')
    T = readtable('exp1_main.csv');
    M = nan(5, 5);
    for m = 1:numel(methods)
        sel = strcmp(T.method, methods{m});
        v = T.obj(sel);
        M(1:numel(v), m) = v;
    end
    fig = figure('Position', [70 70 620 400], 'Color', 'w');
    boxplot(M, mname, 'Colors', col(1:5,:), 'Symbol', 'o');
    ylabel('objective'); grid on; box on
    title('Five operator policies over five seeds', 'FontSize', 10);
    print(fig, 'fig_f5_boxplot.png', '-dpng', '-r260'); close(fig);
    fprintf('wrote fig_f5_boxplot.png\n');
end
end
