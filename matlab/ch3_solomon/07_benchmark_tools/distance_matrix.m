function D = distance_matrix(inst, mode)
%DISTANCE_MATRIX  Distance matrix for a VRPTW instance.
%
%   D = distance_matrix(inst)            % unrounded Euclidean  <-- USE THIS
%   D = distance_matrix(inst, 'round')   % rounded, for other purposes
%
% WHICH ONE THE BENCHMARK USES -- MEASURED, NOT GUESSED
%   The published best-known value for c1_2_1 is 2704.5678.  Evaluating the
%   published routes of that same instance gives
%
%       unrounded : 2704.5678   exact match
%       rounded   : 2690.0000   14.57 too low
%
%   so the objective uses UNROUNDED distances.  A sum of integers cannot have
%   four decimals, and that is the entire argument.
%
%   This was a real bug in this project: with rounded distances a run reported
%   2690 and appeared 0.54% BETTER than the best known solution, which is the
%   most damaging thing a results table can show.  check_bks_convention.m now
%   guards against a recurrence by reproducing the published value end to end.
%
%   For the Nanjing case the matrix comes from a real road network and is not
%   built by this function at all.

    if nargin < 2, mode = 'exact'; end

    dx = inst.x - inst.x';
    dy = inst.y - inst.y';
    D  = sqrt(dx.^2 + dy.^2);

    switch lower(mode)
        case {'round', 'rounded', 'int'}
            D = round(D);
        case {'exact', 'float'}
            % leave as is
        otherwise
            error('distance_matrix:mode', 'unknown mode ''%s''', mode);
    end
end
