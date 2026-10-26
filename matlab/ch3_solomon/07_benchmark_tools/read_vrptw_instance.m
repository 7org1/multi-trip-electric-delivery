function inst = read_vrptw_instance(filename)
%READ_VRPTW_INSTANCE  Parse a Solomon / Gehring-Homberger VRPTW instance file.
%
%   inst = read_vrptw_instance('c1_2_1.txt')
%
% Both benchmark families use the same layout, so one parser covers them:
%
%       C101                        <- instance name (optional)
%
%       VEHICLE
%       NUMBER     CAPACITY
%         25         200            <- nVehicles, capacity
%
%       CUSTOMER
%       CUST NO. XCOORD. YCOORD. DEMAND READY TIME DUE DATE SERVICE TIME
%          0       40      50      0       0       1236      0
%          1       45      68     10     912        967     90
%          ...
%
% WHAT IT DOES NOT DO
%   No hard-coded column positions and no reliance on the header wording, so a
%   small formatting difference between the Solomon files and the Homberger
%   files cannot silently shift a column.  Rows are recognised by having exactly
%   seven numeric fields; the vehicle block by being the first two-number line
%   after the word VEHICLE.
%
% OUTPUT (struct)
%   inst.name      instance name (string)
%   inst.n         number of CUSTOMERS (excluding the depot)
%   inst.Q         vehicle capacity
%   inst.m         number of available vehicles
%   inst.x         [n+1 x 1] x coordinates, index 1 = depot
%   inst.y         [n+1 x 1] y coordinates
%   inst.demand    [n+1 x 1] demands, depot = 0
%   inst.ready     [n+1 x 1] earliest service start
%   inst.due       [n+1 x 1] latest service start
%   inst.service   [n+1 x 1] service duration
%   inst.id        [n+1 x 1] original customer ids
%
% NOTES
%   * Rows are sorted by customer id, so row k always corresponds to customer
%     k-1 regardless of the order they appear in the file.
%   * Grid distances in these benchmarks are EUCLIDEAN and are normally rounded
%     to the nearest integer to reproduce the published best-known values.  Use
%     distance_matrix(inst, 'round') for that.

    txt = fileread(filename);
    lines = regexp(txt, '\r\n|\r|\n', 'split');

    % ------------------------------------------------------------ instance name
    inst.name = '';
    for k = 1:min(numel(lines), 5)
        s = strtrim(lines{k});
        if ~isempty(s)
            inst.name = strrep(s, char(9), ' ');
            break;
        end
    end

    % -------------------------------------------------------- vehicle capacity
    [inst.m, inst.Q] = parse_vehicle_block(lines);

    % ------------------------------------------------------------- customers
    [ids, x, y, dem, rdy, due, srv] = parse_customer_rows(lines);

    if isempty(ids)
        error('read_vrptw_instance:norows', ...
              'no customer rows found in %s', filename);
    end

    % sort by original id so row k is customer k-1
    [ids, ord] = sort(ids(:));
    x = x(ord); y = y(ord); dem = dem(ord);
    rdy = rdy(ord); due = due(ord); srv = srv(ord);

    if ids(1) ~= 0
        error('read_vrptw_instance:nodepot', ...
              'the first customer id must be 0 (the depot), got %d', ids(1));
    end

    inst.n = numel(ids) - 1;
    inst.id      = ids;
    inst.x       = x;
    inst.y       = y;
    inst.demand  = dem;
    inst.ready   = rdy;
    inst.due     = due;
    inst.service = srv;

    if isempty(inst.m) || isnan(inst.m)
        inst.m = inf;   % vehicle count not stated: treat as unbounded
    end

    % ------------------------------------------------------------ sanity check
    if numel(unique(ids)) ~= numel(ids)
        warning('read_vrptw_instance:dupid', 'duplicate customer ids found');
    end
    if any(due < rdy)
        warning('read_vrptw_instance:badwindow', ...
                'customer(s) with due < ready: %s', mat2str(find(due < rdy)'-1));
    end
end


% ================================================================ helpers

function [nveh, cap] = parse_vehicle_block(lines)
%PARSE_VEHICLE_BLOCK  Read the two numbers after the word VEHICLE.
    nveh = NaN; cap = NaN;

    startIdx = 0;
    for k = 1:numel(lines)
        if ~isempty(strfind(upper(lines{k}), 'VEHICLE'))
            startIdx = k;
            break;
        end
    end
    if startIdx == 0
        % no VEHICLE header: fall back to the first two-number line
        startIdx = 1;
    end

    for k = startIdx:numel(lines)
        v = sscanf(strtrim(lines{k}), '%f');
        if numel(v) == 2
            nveh = v(1);
            cap  = v(2);
            return;
        end
        if k - startIdx > 4
            break;   % do not scan far past the header
        end
    end
end


function [ids, x, y, dem, rdy, due, srv] = parse_customer_rows(lines)
%PARSE_CUSTOMER_ROWS  Any line holding exactly seven numbers is a customer row.
    ids = []; x = []; y = []; dem = []; rdy = []; due = []; srv = [];

    % start after the word CUSTOMER when present, so header numbers in the
    % VEHICLE block are never mistaken for customers
    startIdx = 1;
    for k = 1:numel(lines)
        if ~isempty(strfind(upper(lines{k}), 'CUSTOMER'))
            startIdx = k + 1;
            break;
        end
    end

    for k = startIdx:numel(lines)
        s = strtrim(lines{k});
        if isempty(s) || isempty(regexp(s, '^[\s0-9eE\.\+\-]+$', 'once'))
            continue;
        end
        v = sscanf(s, '%f');
        if numel(v) == 7
            ids(end+1, 1) = v(1);  %#ok<AGROW>
            x(end+1, 1)   = v(2);  %#ok<AGROW>
            y(end+1, 1)   = v(3);  %#ok<AGROW>
            dem(end+1, 1) = v(4);  %#ok<AGROW>
            rdy(end+1, 1) = v(5);  %#ok<AGROW>
            due(end+1, 1) = v(6);  %#ok<AGROW>
            srv(end+1, 1) = v(7);  %#ok<AGROW>
        end
    end
end
