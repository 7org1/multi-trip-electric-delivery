function routes = vrptw_construct(S, order)
%VRPTW_CONSTRUCT  Build a feasible VRPTW solution by sequential insertion.
%
%   routes = vrptw_construct(S)
%   routes = vrptw_construct(S, order)
%
% Customers are taken in an order (default: earliest due date first, which is
% the classic rule for time-window problems) and each is placed at its cheapest
% feasible position, opening a new route when that is cheapest.  The result is
% always feasible for the benchmarks used here, where the fleet is generous and
% the binding constraint is the time windows.

    if nargin < 2 || isempty(order)
        [~, order] = sort(S.due(2:end));
        order = order(:)' + 1;
    end

    routes = {};
    for j = order
        [r, p, ~, found] = vrptw_insert_best(S, routes, j, true);
        if ~found
            % should not happen while numel(routes) < S.m; keep the customer
            % anyway so the construction never drops demand silently
            routes{end+1} = j;
            continue;
        end
        if r > numel(routes)
            routes{end+1} = j;
        else
            rt = routes{r};
            routes{r} = [rt(1:p-1), j, rt(p:end)];
        end
    end

    % drop empty routes
    keep = ~cellfun(@isempty, routes);
    routes = routes(keep);
end
