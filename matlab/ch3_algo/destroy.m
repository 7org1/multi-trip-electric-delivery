function [removed, partial] = destroy(C, trips, mode, q)
% DESTROY  The three neighbourhoods of Chapter 3.
%
%   'random'  a uniformly drawn set of points
%   'worst'   the points whose removal saves the most distance
%   'sector'  a contiguous block of the polar order around the depot, which is the
%             operator that exploits congestion being spatially clustered
n = 0;
for k = 1:numel(trips), n = n + numel(trips{k}); end
if n == 0, removed = []; partial = trips; return, end
q = min(q, n);

allC = zeros(n, 1); allK = zeros(n, 1); allI = zeros(n, 1);
m = 0;
for k = 1:numel(trips)
    for i = 1:numel(trips{k})
        m = m + 1;
        allC(m) = trips{k}(i); allK(m) = k; allI(m) = i;
    end
end

switch mode
    case 'random'
        sel = randperm(n, q);
    case 'worst'
        save = zeros(n, 1);
        for m = 1:n
            t = trips{allK(m)};
            i = allI(m);
            a = 1; if i > 1, a = t(i-1); end
            b = 1; if i < numel(t), b = t(i+1); end
            save(m) = C.D(a, allC(m)) + C.D(allC(m), b) - C.D(a, b);
        end
        [~, ord] = sort(save, 'descend');
        sel = ord(1:q);
    case 'trip'
        % remove one whole trip, the only move that can reduce the trip count
        k = randi(numel(trips));
        sel = find(allK == k);
        if numel(sel) > q
            sel = sel(1:q);
        end
    otherwise   % sector
        ang = atan2(C.lat(allC) - C.lat(1), C.lon(allC) - C.lon(1));
        st = rand * 2 * pi;
        key = mod(ang - st, 2 * pi);
        [~, ord] = sort(key);
        sel = ord(1:q);
end

removed = sort(allC(sel))';
drop = false(n, 1); drop(sel) = true;
partial = {};
for k = 1:numel(trips)
    t = trips{k};
    keep = true(1, numel(t));
    for i = 1:numel(t)
        if any(allK(sel) == k & allI(sel) == i)
            keep(i) = false;
        end
    end
    if any(keep), partial{end+1} = t(keep); end %#ok<AGROW>
end
end
