function plot_routes_grid(C, routes, outPng, ttls)
% PLOT_ROUTES_GRID  One panel per vehicle, three rows by two columns.
%
%   Each panel draws the road network in light grey, the trips of one vehicle along
%   the actual shortest paths, and the depot.  The title of a panel gives the number
%   of trips and the hours of departure and return.
%
%   The panels are packed with tiledlayout and compact spacing, so the figure carries
%   no wasted white space between the rows.

F = numel(routes);
if nargin < 3 || isempty(outPng), outPng = 'routes_grid.png'; end
if nargin < 4 || isempty(ttls), ttls = 'Routes of the six vehicles over one day'; end

BASE = 'C:\Users\YJZT\Desktop\route\build\osm';
[rx, ry] = road_segments(BASE);
bnd = C.bnd;
tripCol = [0.85 0.10 0.10; 0.10 0.30 0.85; 0.10 0.60 0.15; 0.95 0.55 0.05];

fig = figure('Position', [40 20 880 1240], 'Color', 'w');
tl = tiledlayout(fig, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

for v = 1:F
    nexttile;
    hold on
    plot(rx, ry, '-', 'Color', [0.88 0.88 0.88], 'LineWidth', 0.35);
    for i = 1:size(bnd, 1)
        plot([bnd(i,1) bnd(i,3)], [bnd(i,2) bnd(i,4)], 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
    end
    [okv, ~, ~, ~, ~, dep, ret] = route_eval(C, routes{v}, C.TSTART, C.B);
    nt = numel(routes{v});
    for k = 1:nt
        col = tripCol(mod(k-1, size(tripCol,1)) + 1, :);
        trip = routes{v}{k};
        seq = [1, trip(:)', 1];
        for j = 1:numel(seq)-1
            [px, py] = path_xy(C, seq(j), seq(j+1));
            if numel(px) > 1
                plot(px, py, '-', 'Color', col, 'LineWidth', 1.1);
            end
        end
        plot(C.lon(trip), C.lat(trip), 'o', 'MarkerSize', 2.6, ...
            'MarkerFaceColor', col, 'MarkerEdgeColor', 'none');
    end
    plot(C.lon(1), C.lat(1), 'p', 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w', 'MarkerSize', 14);
    xlim([min(C.lon)-0.015, max(C.lon)+0.015]);
    ylim([min(C.lat)-0.015, max(C.lat)+0.015]);
    daspect([1, 1/cosd(mean(C.lat)), 1]);
    if okv && numel(dep) == nt
        title(sprintf('vehicle %d, %d trips, %s to %s', v, nt, hhmm(dep(1)), hhmm(ret(end))), 'FontSize', 8);
    else
        title(sprintf('vehicle %d, %d trips', v, nt), 'FontSize', 8);
    end
    set(gca, 'FontSize', 6, 'XTick', [], 'YTick', []);
    box on
end
title(tl, ttls, 'FontSize', 11);
print(fig, outPng, '-dpng', '-r260');
close(fig);
fprintf('wrote %s\n', outPng);
end


function s = hhmm(h)
m = round((h - floor(h)) * 60);
if m == 60, s = sprintf('%02d:00', floor(h) + 1); return, end
s = sprintf('%02d:%02d', floor(h), m);
end


function [x, y] = road_segments(BASE)
f = fullfile(BASE, "district_edges.csv");
if ~isfile(f)
    x = []; y = []; return
end
T = readtable(f, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
ids = readtable(fullfile(BASE, "district_nodes.csv"), 'Delimiter', ',', 'VariableNamingRule', 'preserve');
map = containers.Map(ids.node_id, 1:height(ids));
u = cell2mat(values(map, num2cell(T.u)));
v = cell2mat(values(map, num2cell(T.v)));
x = nan(3 * height(T), 1); y = x;
x(1:3:end) = ids.lon(u);  x(2:3:end) = ids.lon(v);
y(1:3:end) = ids.lat(u);  y(2:3:end) = ids.lat(v);
end


function [xs, ys] = path_xy(C, s, t)
src = C.snap(C.orig(s));
dst = C.snap(C.orig(t));
row = C.orig(s);
xs = []; ys = [];
if src == dst, return, end
cur = dst;
guard = 0;
while cur ~= src && guard < 200000
    xs(end+1) = C.nodeLon(cur); %#ok<AGROW>
    ys(end+1) = C.nodeLat(cur); %#ok<AGROW>
    nxt = C.PR(row, cur);          % the table is one based, 0 marks no predecessor
    if nxt <= 0, xs = []; ys = []; return, end
    cur = nxt;
    guard = guard + 1;
end
xs(end+1) = C.nodeLon(src);
ys(end+1) = C.nodeLat(src);
xs = fliplr(xs);
ys = fliplr(ys);
end
