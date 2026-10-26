function C = case_load(varargin)
% CASE_LOAD  Load the case from case.mat and expand the split deliveries.
%
%   C = case_load()            capacity 800, windows 12/17/19
%   C = case_load('cap',600,'windows',[12 17 19])
%
%   A station whose demand exceeds one load cannot be served by a single trip, so
%   it is split into virtual points at the same place, one per load.  The number of
%   distinct demand points does not change; only the representation does.
%
%   Fields of C
%     D        distance matrix in km, row 1 is the depot
%     Tall     9 x n x n travel times in hours, one slice per speed band
%     lon lat  coordinates of the points
%     demand   parcels per point, the depot carries none
%     serviceH service time in hours
%     winS winE  window opening and closing hour
%     Q B SMIN PCH LOADH TSTART TEND FLEET OMEGA   the parameters of the model

p = inputParser;
p.addParameter('cap', 1200);
p.addParameter('windows', [12 17 19]);
p.addParameter('file', 'case.mat');
p.parse(varargin{:});
o = p.Results;

f = o.file;
if ~isfile(f)
    here = fileparts(mfilename('fullpath'));
    cand = fullfile(here, '..', 'data', f);
    if isfile(cand), f = cand; end
end
S = load(f);

C.D = S.D;
C.Tall = S.Tall;
C.lon = S.lon(:);
C.lat = S.lat(:);
C.demand = S.demand(:);
C.serviceH = S.serviceH(:);
C.winS = S.winS(:);
C.winE = S.winE(:);
C.name = strcat("P", string(1:numel(S.demand)));
C.snap = S.snap(:);
C.PR = S.PR;
C.nodeLon = S.nodeLon(:);
C.nodeLat = S.nodeLat(:);
C.bnd = S.bnd;

% the three window bands, by straight line distance from the depot
w = o.windows;
for i = 2:numel(C.demand)
    dd = C.D(1, i);
    if dd < 5
        C.winE(i) = w(1);
    elseif dd < 12
        C.winE(i) = w(2);
    else
        C.winE(i) = w(3);
    end
end

C.Q = o.cap;
C.B = 40.0;
C.SMIN = 8.0;
C.PCH = 7.0;
C.LOADH = 0.25;
C.TSTART = 6.0;
C.TEND = 20.0;
C.FLEET = 8;
C.OMEGA = 50.0;
C.BANDS = [0 6; 6 7; 7 9; 9 11; 11 13; 13 17; 17 19; 19 22; 22 24];

C = expand_points(C);
end


function C = expand_points(C)
% split a station whose demand exceeds one load into several virtual points
n0 = numel(C.demand);
idx = 1; dem = 0;
for i = 2:n0
    d = C.demand(i);
    k = ceil(d / C.Q);
    if k <= 1
        idx(end+1) = i; dem(end+1) = d; %#ok<AGROW>
    else
        parts = repmat(floor(d / k), 1, k);
        parts(1) = parts(1) + d - sum(parts);
        for j = 1:k
            idx(end+1) = i; dem(end+1) = parts(j); %#ok<AGROW>
        end
    end
end
C.orig = idx(:);
C.demand = dem(:);
C.D = C.D(idx, idx);
C.Tall = C.Tall(:, idx, idx);
C.lon = C.lon(idx);
C.lat = C.lat(idx);
C.serviceH = C.serviceH(idx);
C.winS = C.winS(idx);
C.winE = C.winE(idx);
C.name = C.name(idx);
C.n = numel(C.demand);
end
