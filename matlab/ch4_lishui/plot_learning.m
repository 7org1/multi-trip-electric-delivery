function plot_learning(seeds, budget, F, cap, outPng)
% PLOT_LEARNING  Two figures about the policy, one run per figure.
%
%   (a) the share of each operator against the hour at which the destroyed trips run,
%       drawn as a stacked area so that the shift from block destruction in the
%       morning to point destruction in the evening can be seen directly;
%   (b) the cumulative share of each operator against the iteration, which shows
%       whether the bandit learns anything or keeps sampling at random.

if nargin < 1 || isempty(seeds), seeds = 1:3; end
if nargin < 2 || isempty(budget), budget = 20; end
if nargin < 3 || isempty(F), F = 6; end
if nargin < 4 || isempty(cap), cap = 1200; end
if nargin < 5 || isempty(outPng), outPng = 'fig_learning.png'; end

arms = {'sector', 'worst', 'random'};
col = [0.85 0.10 0.10; 0.10 0.30 0.85; 0.10 0.60 0.15];

CLK = []; ARM = []; ITER = []; CUM = {};
for s = seeds
    C = case_load('cap', cap, 'windows', [12 17 19]);
    [~, o] = solve_day(C, F, 'CBLNS', budget, s);
    L = o.log;
    CLK = [CLK; L(:,2)];       %#ok<AGROW>
    ARM = [ARM; L(:,3)];       %#ok<AGROW>
    ITER = [ITER; L(:,1)];     %#ok<AGROW>
    c = zeros(size(L,1), 3);
    for k = 1:3
        c(:,k) = cumsum(L(:,3) == k) ./ (1:size(L,1))';
    end
    CUM{end+1} = c;            %#ok<AGROW>
    fprintf('seed %d done: %d iterations, objective %.1f\n', s, o.iters, o.obj);
end

% ---------- (a) share by hour ----------
edges = 6:0.5:20;
idx = discretize(CLK, edges);
keep = ~isnan(idx);
nbin = numel(edges) - 1;
sh = zeros(nbin, 3);
for b = 1:nbin
    sel = idx == b & keep;
    if any(sel)
        sh(b,:) = accumarray(ARM(sel), 1, [3 1])' / sum(sel);
    else
        sh(b,:) = [NaN NaN NaN];
    end
end
% a bin with few decisions is noisy, so smooth with a three bin window and drop the
% bins at the edges where the count falls below ten
cnt = zeros(nbin,1);
for b = 1:nbin, cnt(b) = sum(idx == b & keep); end
shs = sh;
for b = 2:nbin-1
    w = cnt(b-1:b+1);
    if all(~isnan(sh(b,:)))
        shs(b,:) = (sh(b-1,:)*w(1) + sh(b,:)*w(2) + sh(b+1,:)*w(3)) / sum(w);
    end
end
good = cnt >= 5 & ~isnan(shs(:,1));

fig = figure('Position', [60 60 980 420], 'Color', 'w');
tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile; hold on
xc = edges(1:end-1) + 0.25;
area(xc(good), shs(good,:), 'LineStyle', 'none');
for k = 1:3, area(xc(good), shs(good,k), 'FaceColor', col(k,:), 'LineStyle', 'none'); end
ylim([0 1]); xlim([min(xc(good)) max(xc(good))]);
xlabel('hour at which the destroyed trips run'); ylabel('share of decisions');
legend(arms, 'Location', 'eastoutside'); box on
title(sprintf('(a) operator share by hour, %d seeds', numel(seeds)), 'FontSize', 10);

% ---------- (b) cumulative share ----------
nexttile; hold on
for k = 1:3
    m = [];
    for s = 1:numel(CUM), m = [m; CUM{s}(:,k)]; end %#ok<AGROW>
    L = min(cellfun(@(x) size(x,1), CUM));
    mm = zeros(L, numel(CUM));
    for s = 1:numel(CUM), mm(:,s) = CUM{s}(1:L,k); end
    plot(1:L, mean(mm,2), '-', 'Color', col(k,:), 'LineWidth', 1.4);
end
ylim([0 1]); xlabel('iteration'); ylabel('cumulative share');
legend(arms, 'Location', 'eastoutside'); box on
title('(b) cumulative share against iteration', 'FontSize', 10);
grid on

print(fig, outPng, '-dpng', '-r260');
close(fig);
fprintf('wrote %s\n', outPng);
end
