function out = probe_cblns(budget, seed, F, cap)
% PROBE_CBLNS  One long run of the proposed method, with the operator mix by regime.
%
%   The point is to see whether a budget large enough for the bandit to see thousands
%   of samples changes the policy it settles on.  The mix is reported per congestion
%   regime, because that is the context the policy is supposed to condition on:
%   light (s <= 0.35), moderate, and heavy (s >= 0.9).

if nargin < 1, budget = 200; end
if nargin < 2, seed = 1; end
if nargin < 3, F = 5; end
if nargin < 4, cap = 2400; end

C = case_load('cap', cap, 'windows', [12 17 19]);
t0 = tic;
[~, o] = solve_day(C, F, 'CBLNS', budget, seed);
el = toc(t0);

nPick = o.share;                      % 3 regimes x 3 operators, raw counts
reg = {'light', 'moderate', 'heavy'};
arms = {'sector', 'worst', 'random'};

fprintf('\nCBLNS  budget %g s  seed %d  fleet %d  cap %d\n', budget, seed, F, cap);
fprintf('objective %.1f   trips %d   distance %.1f   iterations %d   %.0f s\n', ...
    o.obj, o.trips, o.distance, o.iters, el);
fprintf('\noperator mix by congestion regime (row share)\n');
fprintf('%-9s %8s %8s %8s %8s\n', 'regime', 'n', 'sector', 'worst', 'random');
for g = 1:3
    n = sum(nPick(g, :));
    if n == 0
        fprintf('%-9s %8d %8s %8s %8s\n', reg{g}, 0, '-', '-', '-');
        continue
    end
    fprintf('%-9s %8d %8.3f %8.3f %8.3f\n', reg{g}, n, nPick(g,1)/n, nPick(g,2)/n, nPick(g,3)/n);
end
fprintf('%-9s %8d %8.3f %8.3f %8.3f\n', 'overall', sum(nPick(:)), ...
    sum(nPick(:,1))/sum(nPick(:)), sum(nPick(:,2))/sum(nPick(:)), sum(nPick(:,3))/sum(nPick(:)));

% keep the run on disk so that the mix survives the session
fid = fopen(sprintf('probe_cblns_%ds_seed%d.txt', round(budget), seed), 'w');
fprintf(fid, 'CBLNS budget %g s seed %d fleet %d cap %d\n', budget, seed, F, cap);
fprintf(fid, 'objective %.2f trips %d distance %.2f iterations %d seconds %.1f\n\n', ...
    o.obj, o.trips, o.distance, o.iters, el);
fprintf(fid, 'regime, decisions, sector, worst, random\n');
for g = 1:3
    n = sum(nPick(g, :));
    if n == 0, continue, end
    fprintf(fid, '%s,%d,%.4f,%.4f,%.4f\n', reg{g}, n, nPick(g,1)/n, nPick(g,2)/n, nPick(g,3)/n);
end
fprintf(fid, 'overall,%d,%.4f,%.4f,%.4f\n', sum(nPick(:)), ...
    sum(nPick(:,1))/sum(nPick(:)), sum(nPick(:,2))/sum(nPick(:)), sum(nPick(:,3))/sum(nPick(:)));
fclose(fid);

out = o;
out.nPick = nPick;
out.seconds = el;
fprintf('\nwrote probe_cblns_%ds_seed%d.txt\n', round(budget), seed);
end
