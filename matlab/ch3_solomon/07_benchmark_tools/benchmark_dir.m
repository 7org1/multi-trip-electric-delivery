function d = benchmark_dir()
%BENCHMARK_DIR  Location of the benchmark DATA, which lives apart from the tools.
%
% The data directory is kept free of code so that a reviewer can open it and see
% only the standard instance files and the best-known-solution table, with no
% chance of confusing a helper script for part of the benchmark.
%
%   build/07_benchmark/        instances200/  +  gh200_bks.csv   (data, read-only)
%   build/07_benchmark_tools/  this file and the other .m helpers (code)

    here = fileparts(mfilename('fullpath'));
    d = fullfile(here, '..', '07_benchmark');
end
