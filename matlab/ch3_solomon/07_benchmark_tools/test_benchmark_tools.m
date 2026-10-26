function test_benchmark_tools()
%TEST_BENCHMARK_TOOLS  Verify the instance parser, BKS table and gap report.
%
% Run before trusting the tools on real instance files.  A parser that silently
% shifts a column produces results that look plausible and are wrong, so this
% test checks the numbers against values that can be verified by hand.

    here = fileparts(mfilename('fullpath'));
    addpath(here);

    fprintf('=== 1. parse a Solomon-format file ===\n');
    inst = read_vrptw_instance(fullfile(here, '_test_C101.txt'));
    fprintf('  name        : %s\n', inst.name);
    fprintf('  customers n : %d      (expect 25)\n', inst.n);
    fprintf('  capacity  Q : %g      (expect 200)\n', inst.Q);
    fprintf('  vehicles  m : %g      (expect 25)\n', inst.m);
    fprintf('  depot       : (%.0f, %.0f)   (expect 40, 50)\n', inst.x(1), inst.y(1));
    fprintf('  demand sum  : %g\n', sum(inst.demand));
    ok = (inst.n == 25) && (inst.Q == 200) && (inst.m == 25) ...
         && inst.x(1) == 40 && inst.y(1) == 50;
    fprintf('  parser      : %s\n\n', ternary(ok, 'PASS', 'FAIL'));

    fprintf('=== 2. distance matrix, rounded vs exact ===\n');
    D1 = distance_matrix(inst);
    D2 = distance_matrix(inst, 'round');
    fprintf('  D(1,2) exact = %.6f\n', D1(1,2));
    fprintf('  D(1,2) round = %.0f\n', D2(1,2));
    fprintf('  sum of rounded departures from depot = %g\n\n', sum(D2(1,2:end)));

    fprintf('=== 3. load the best-known table ===\n');
    bks = load_bks(fullfile(benchmark_dir(), 'gh200_bks.csv'));
    f = fieldnames(bks);
    fprintf('  instances in table : %d   (expect 60)\n', numel(f));
    if isfield(bks, 'c1_2_1')
        fprintf('  c1_2_1 : %d routes, %.4f\n', bks.c1_2_1.routes, bks.c1_2_1.dist);
    end
    if isfield(bks, 'rc2_2_10')
        fprintf('  rc2_2_10 : %d routes, %.4f\n', bks.rc2_2_10.routes, bks.rc2_2_10.dist);
    end
    fprintf('  bks table    : %s\n\n', ternary(numel(f) == 60, 'PASS', 'FAIL'));

    fprintf('=== 4. gap report ===\n');
    report_gap('c1_2_1', bks.c1_2_1.dist,          bks.c1_2_1.routes, bks);
    report_gap('c1_2_1', bks.c1_2_1.dist * 1.02,   bks.c1_2_1.routes, bks);
    report_gap('c1_2_1', bks.c1_2_1.dist,          bks.c1_2_1.routes + 1, bks);

    fprintf('\nall checks done\n');
end


function s = ternary(c, a, b)
    if c, s = a; else, s = b; end
end
