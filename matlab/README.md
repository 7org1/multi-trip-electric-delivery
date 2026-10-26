# Implementation map

Every folder holds one layer, so a file can be read and checked against the chapter that
defines it.  Run `setup_paths` once after opening MATLAB; after that any driver works
from any current folder.

```
exp\matlab\
    setup_paths.m          put the folders below on the search path
    ch2_model\             the model, equations (2-1) to (2-8)
    ch3_algo\              the solver of Chapter 3
    experiments_static\    the Chapter 3 solver applied to the case, one trip per vehicle
    ch4_lishui\            the whole-day solver of Chapter 4 and its drivers
    ch3_solomon\           the Solomon benchmarks, their tools and the algorithm
    data\                  case.mat, the matrices of the case
    results\               every csv and txt a run produced
```

## ch2_model, the model

| File | Equation |
|---|---|
| `arc_cost.m` | (2-1) energy and (2-2) travel time on an arc |
| `trip_dist.m` | (2-8) length of a trip |
| `trip_eval.m` | walks a trip and checks capacity, windows and the state of charge |
| `sol_cost.m` | (2-5) the objective, trip count first and distance second |
| `speed_band.m` | index of the speed band that contains an hour |
| `congestion_band.m` | which of the three congestion regimes an hour belongs to |
| `congestion.m` | share of a trip's driving time in each regime |
| `fleet_congestion.m` | the three shares of a whole solution |
| `slack_c.m` | hours left before a point can no longer be served |

## ch3_algo, the solver of Chapter 3

| File | Role |
|---|---|
| `cblns_v3.m` | contextual bandit large neighbourhood search, one trip per vehicle |
| `destroy.m` | the three neighbourhoods, sector, worst and random |
| `best_insert.m` | cheapest feasible insertion position of one point |
| `insert_all.m` | greedy repair, the same in every method |

## experiments_static, the Chapter 3 solver on the case

These drivers run the Chapter 3 solver on the Lishui case with one trip per vehicle.
They produced the comparison that motivated Chapter 4 and are kept because the numbers
in the paper's earlier draft came from them.

| File | Role |
|---|---|
| `run_method.m` | one solver, one run, one budget |
| `run_all.m` | every method, one row per run |
| `tune_cblns.m` | grid over the cooling rule and the guards |
| `baselines_only.m` | the four baselines alone |
| `cblns_only.m` | the proposed method alone |
| `insert_relaxed.m` | repair that gives up on a point it cannot place |
| `verify_case.m` | fourteen checks against the equations of Chapters 2 and 3 |

## ch4_lishui, the whole-day solver

| File | Role |
|---|---|
| `case_load.m` | reads `data\case.mat`, expands points whose demand exceeds one load |
| `route_eval.m` | drives one vehicle's sequence of trips, charging as needed |
| `routes_cost.m` | objective of a whole day |
| `build_routes.m` | greedy construction, one trip per vehicle per round |
| `solve_day.m` | the search, one call for one whole day |
| `run_day.m` | the five operator policies over five seeds |
| `run_base_rerun.m` | the four baselines, measured with the same code |
| `probe_cblns.m` | one long run, reporting the operator mix by regime |
| `plot_routes_grid.m` | the 3 by 2 figure, one panel per vehicle, one colour per trip |

## ch3_solomon, the benchmarks of Chapter 3

A copy of the three sibling folders that hold the Solomon and Gehring-Homberger
work.  They were copied rather than moved, and kept under their original names,
because every file there resolves its data through a path relative to its own folder;
a copy that preserves the three names keeps all of those paths valid.

| Folder | Files | Role |
|---|---|---|
| `ch3_solomon\07_benchmark` | 62 | `instances200\` with 60 instances and the best-known table `gh200_bks.csv` |
| `ch3_solomon\07_benchmark_tools` | 27 | `read_vrptw_instance`, `benchmark_dir`, `load_bks`, `solve_alns`, `solve_vns`, evaluation |
| `ch3_solomon\08_myalgo` | 44 code files | `solve_rlgbka`, the policy, the operators, the training and the analysis scripts |

The originals are still in `build\07_benchmark`, `build\07_benchmark_tools` and
`build\08_myalgo`.  Edit one place only, or the two copies drift apart.

Check that the copy is intact

```
setup_paths
load_bks()                                  % 60 instances, c1_2_1 gives 20 vehicles and 2704.6 km
P = read_vrptw_instance(fullfile(benchmark_dir(), 'instances200', 'C1_2_1.TXT'));
numel(P.demand) - 1                         % 200 customers
```

## Reproducing a number

```
setup_paths
C = case_load();                          % 200 points, 23,997 parcels, 1,200 per trip
[R, o] = solve_day(C, 6, 'CBLNS', 20, 1);  % about 25 s
o.obj, o.trips, o.distance                % 2,078.5, 21, 1,028.5 for seed 1

run_day(20, 1:5, 6, 1200)                 % the five policies, five seeds
run_base_rerun(20, 1:5, 6, 1200)          % the four baselines with the same code
```
