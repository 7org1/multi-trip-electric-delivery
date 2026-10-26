function time_distance_matrix()
%TIME_DISTANCE_MATRIX  How expensive is the distance matrix really?
%
% Written because the claim "caching saves 10x" needs to be checked rather than
% asserted.  If building the matrix costs microseconds, caching it across the
% ten instances of a class saves microseconds, and the optimisation is noise.
% It only becomes material if the matrix is expensive -- which is the case once
% the benchmark is extended with time-dependent travel times.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    p = fullfile(benchmark_dir(), 'instances200', 'C1_2_1.TXT');
    inst = read_vrptw_instance(p);

    fprintf('instance %s : n = %d, matrix size %dx%d\n\n', ...
            inst.name, inst.n, inst.n+1, inst.n+1);

    % warm up so JIT cost is not counted
    D = distance_matrix(inst, 'round');

    N = 200;
    tic;
    for k = 1:N
        D = distance_matrix(inst, 'round');
    end
    tMat = toc / N;

    fprintf('distance_matrix        : %8.1f us per call\n', tMat * 1e6);
    fprintf('per class (10 instances): %8.3f ms\n', 10 * tMat * 1e3);
    fprintf('all 60 instances        : %8.3f ms\n\n', 60 * tMat * 1e3);

    % ---- what a time-dependent extension would cost
    T = 24;   % hourly snapshots, the usual choice
    fprintf('=== if the matrix becomes time-dependent (%d snapshots) ===\n', T);
    fprintf('  matrices per instance       : %d\n', T);
    fprintf('  matrices for all 60         : %d\n', 60 * T);
    fprintf('  cost if recomputed each time: %.2f s\n', 60 * T * tMat);
    fprintf('  cost with per-class caching  : %.2f s  (10x less)\n', 6 * T * tMat);
    fprintf('\n');

    % ---- but the real cost of a time-dependent matrix is the shortest paths,
    % not this arithmetic.  Compare against a realistic road-network query.
    fprintf('=== the part that actually costs ===\n');
    fprintf('  this function only does 201x201 arithmetic.\n');
    fprintf('  a time-dependent matrix from a real network needs one\n');
    fprintf('  time-dependent shortest-path run per (origin, snapshot):\n');
    fprintf('      201 origins x %d snapshots = %d runs\n', T, 201*T);
    fprintf('  at 50 ms per run that is %.0f s per instance.\n', 201*T*0.05);
    fprintf('  caching the *distance* matrix saves nothing there;\n');
    fprintf('  caching the *shortest-path result* is what matters.\n');
end
