function bks = load_bks(csvfile)
%LOAD_BKS  Read the best-known-solution table (gh200_bks.csv).
%
%   bks = load_bks()                % uses gh200_bks.csv next to this file
%   bks = load_bks('gh400_bks.csv')
%
% Returns a struct keyed by instance name:
%   bks.('c1_2_1').routes    best-known number of vehicles
%   bks.('c1_2_1').dist      best-known total distance
%   bks.('c1_2_1').by        who established it
%
% The table was transcribed from the SINTEF / combopt.org VRPTW pages.  Verify
% against https://www.sintef.no/projectweb/top/vrptw/ before submission, since
% a few values have been improved over the years.

    if nargin < 1 || isempty(csvfile)
        here = fileparts(mfilename('fullpath'));
        csvfile = fullfile(benchmark_dir(), 'gh200_bks.csv');
    end

    fid = fopen(csvfile, 'r');
    if fid < 0
        error('load_bks:open', 'cannot open %s', csvfile);
    end
    c = onCleanup(@() fclose(fid));

    fgetl(fid);                     % header
    bks = struct();
    while true
        L = fgetl(fid);
        if ~ischar(L), break; end
        L = strtrim(L);
        if isempty(L), continue; end
        p = strsplit(L, ',');
        if numel(p) < 3, continue; end
        name = strtrim(p{1});
        f = struct();
        f.routes = str2double(p{2});
        f.dist   = str2double(p{3});
        if numel(p) >= 4
            f.by = strtrim(p{4});
        else
            f.by = '';
        end
        bks.(matlab.lang.makeValidName(name)) = f;
    end
end
