function setup_paths()
% SETUP_PATHS  Put every folder of the implementation on the search path.
%
%   Run this once after opening MATLAB, then the drivers in ch3_algo, experiments_static
%   and ch4_lishui work from any current folder.

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, 'ch2_model'));
addpath(fullfile(here, 'ch3_algo'));
addpath(fullfile(here, 'experiments_static'));
addpath(fullfile(here, 'ch4_lishui'));
addpath(fullfile(here, 'ch3_solomon', '07_benchmark_tools'));
addpath(fullfile(here, 'ch3_solomon', '08_myalgo'));

fprintf('paths added\n');
fprintf('  ch2_model          the model, eq (2-1) to (2-8)\n');
fprintf('  ch3_algo           the solver of Chapter 3\n');
fprintf('  experiments_static the Chapter 3 solver run on the case, one trip per vehicle\n');
fprintf('  ch4_lishui         the whole-day solver of Chapter 4 and its drivers\n');
fprintf('  ch3_solomon        the Solomon benchmarks, the parsing tools and the algorithm\n');
end
