function plot_regime(seeds, budget, F, cap, outPng)
% PLOT_REGIME  One panel per congestion regime, cumulative operator share within it.
%
%   The bandit keeps a separate estimate for each regime, so the question is not what
%   it learned overall but what it learned in each.  Each panel counts only the
%   decisions taken while that regime was the context, and the number of such
%   decisions is printed in the title, because a regime that hardly occurs can carry
%   no policy.

if nargin < 1 || isempty(seeds), seeds = 1:3; end
if nargin < 2 || isempty(budget), budget = 20; end
if nargin < 3 || isempty(F), F = 6; end
if nargin < 4 || isempty(cap), cap = 1200; end
if nargin < 5 || isempty(outPng), outPng = 'fig_e_regime.png'; end

arms = {'sector', 'worst', 'random'};
col = [0.85 0.15 0.15; 0.15 0.35 0.85; 0.15 0.60 0.20];
reg = {'light', 'moderate', 'heavy'};

LOGS = {};
for s = seeds
    C = case_load('cap', cap, 'windows', [12 17 19]);
    [~, o] = solve_day(C, F, 'CBLNS', budget, s);
    LOGS{end+1} = o.log; %#ok<AGROW>
    fprintf('seed %d: %d iterations, objective %.1f\n', s, o.iters, o.obj);
end

fig = figure('Position', [60 60 1180 380], 'Color', 'w');
tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

for g = 1:3
    nexttile; hold on
    hs = gobjects(3, 1);
    ntot = 0;
    Lm = inf;
    for s = 1:numel(LOGS)
        a = LOGS{s}(LOGS{s}(:,4) == g, 3);
        if isempty(a), continue, end
        ntot = ntot + numel(a);
        Lm = min(Lm, numel(a));
    end
    if isinf(Lm)
        for k = 1:3
            hs(k) = plot(nan, nan, '-', 'Color', col(k,:), 'LineWidth', 1.6);
        end
        title(sprintf('(%c) %s, no decision', 'a'+g-1, reg{g}), 'FontSize', 9);
    else
        for k = 1:3
            Mm = [];
            for s = 1:numel(LOGS)
                a = LOGS{s}(LOGS{s}(:,4) == g, 3);
                if numel(a) >= Lm
                    Mm(:, end+1) = cumsum(a(1:Lm) == k) ./ (1:Lm)'; %#ok<AGROW>
                end
            end
            hs(k) = plot(1:Lm, mean(Mm, 2), '-', 'Color', col(k,:), 'LineWidth', 1.6);
        end
        xlim([1 max(2, Lm)]);
        title(sprintf('(%c) %s, %d decisions', 'a'+g-1, reg{g}, ntot), 'FontSize', 9);
    end
    ylim([0 1]);
    xlabel('decision within the regime'); ylabel('cumulative share');
    legend(hs, arms, 'Location', 'eastoutside', 'FontSize', 7);
    grid on; box on
end

print(fig, outPng, '-dpng', '-r260');
close(fig);
fprintf('wrote %s\n', outPng);
end
