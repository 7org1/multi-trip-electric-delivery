function plot_gantt(C, routes, outPng)
% PLOT_GANTT  One row per vehicle, one bar per trip, with the loading and charging gaps.
%
%   The colour of a bar is the congestion regime that takes most of its driving time,
%   so the picture shows at a glance how the day is chained, where the charging falls,
%   and which trips sit in the peaks.

if nargin < 3 || isempty(outPng), outPng = 'fig_gantt.png'; end

F = numel(routes);
regCol = [0.55 0.75 0.95; 0.98 0.80 0.35; 0.90 0.35 0.30];   % light, moderate, heavy
regName = {'light', 'moderate', 'heavy'};

fig = figure('Position', [70 70 900 420], 'Color', 'w');
hold on
for v = 1:F
    y = F - v + 1;
    [ok, ~, ~, ~, ~, dep, ret] = route_eval(C, routes{v}, C.TSTART, C.B);
    if ~ok, continue, end
    for k = 1:numel(dep)
        [sh, ~] = congestion(C, routes{v}{k}, dep(k));
        [~, g] = max(sh);
        patch([dep(k) ret(k) ret(k) dep(k)], [y-0.3 y-0.3 y+0.3 y+0.3], ...
            regCol(g,:), 'EdgeColor', [0.25 0.25 0.25], 'LineWidth', 0.6);
        text(mean([dep(k) ret(k)]), y, sprintf('%d', k), 'HorizontalAlignment', 'center', ...
            'FontSize', 7, 'Color', [0.15 0.15 0.15]);
        if k < numel(dep)
            gap0 = ret(k); gap1 = dep(k+1);
            if gap1 > gap0
                lo = min(C.LOADH, gap1 - gap0);
                patch([gap0 gap0+lo gap0+lo gap0], [y-0.18 y-0.18 y+0.18 y+0.18], ...
                    [0.85 0.85 0.85], 'EdgeColor', 'none');
                if gap1 - gap0 > lo
                    patch([gap0+lo gap1 gap1 gap0+lo], [y-0.18 y-0.18 y+0.18 y+0.18], ...
                        [0.20 0.55 0.20], 'EdgeColor', 'none');
                end
            end
        end
    end
end
yline(0.5, 'k:', 'LineWidth', 0.8);
xline(C.TEND, 'k--', 'LineWidth', 1.0);
xlim([C.TSTART C.TEND + 0.3]);
ylim([0.4 F + 0.6]);
set(gca, 'YTick', 1:F, 'YTickLabel', arrayfun(@(v) sprintf('vehicle %d', F-v+1), 1:F, 'UniformOutput', false));
xlabel('hour of the day'); ylabel('');
h1 = patch(nan, nan, regCol(1,:), 'EdgeColor', [0.25 0.25 0.25]);
h2 = patch(nan, nan, regCol(2,:), 'EdgeColor', [0.25 0.25 0.25]);
h3 = patch(nan, nan, regCol(3,:), 'EdgeColor', [0.25 0.25 0.25]);
h4 = patch(nan, nan, [0.85 0.85 0.85], 'EdgeColor', 'none');
h5 = patch(nan, nan, [0.20 0.55 0.20], 'EdgeColor', 'none');
legend([h1 h2 h3 h4 h5], {regName{:}, 'loading', 'charging'}, 'Location', 'eastoutside', 'FontSize', 7);
grid on
box on
title('One day of the six vehicles; the number in each bar is the trip index', 'FontSize', 10);
print(fig, outPng, '-dpng', '-r260');
close(fig);
fprintf('wrote %s\n', outPng);
end
