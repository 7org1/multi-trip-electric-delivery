# Multi-trip autonomous electric delivery on a real time-dependent network

Reproduction package for the manuscript

> **Multi-Trip Autonomous Electric Delivery on Real Time-Dependent Networks:
> A Congestion-Aware Adaptive Large Neighbourhood Search**

The package contains the model, the search, the case, the experiment drivers and every
result table reported in the paper. Nothing in it is a mock-up: the files in `results/`
are the ones the manuscript quotes.

## What the paper does

A district delivery problem in which one autonomous electric vehicle runs several trips
a day around a single battery, on a road network whose travel times change with the
hour. The model keeps the state of charge as a **constraint** rather than an objective
term, so it stays feasible when energy is short, and the objective is the trip count
first and the distance second. The search picks its destroy operator with a linear
contextual bandit that keeps a separate estimate for each of three congestion regimes.

## Layout

```
matlab/            the implementation, MATLAB R2024a
  setup_paths.m      put every folder on the search path
  README.md          what each file is and which chapter it belongs to
  ch2_model/         the model, equations (2-1) to (2-8)
  ch3_algo/          the solver of Chapter 3
  ch3_solomon/       the Solomon and Gehring-Homberger benchmarks and their code
  experiments_static/  the Chapter 3 solver run on the case
  ch4_lishui/        the whole-day solver of Chapter 4 and the drivers
python/            the scripts that build the case from OpenStreetMap
results/           every csv and summary a run produced
figures/           the figures of the manuscript, 260 dpi
data/              case.mat and the point tables
```

## Reproducing a number

Open MATLAB in `matlab/`, then

```matlab
setup_paths
C = case_load();                        % 200 points, 23,997 parcels, 1,200 per trip
[R, o] = solve_day(C, 6, 'CBLNS', 20, 1);
o.obj, o.trips, o.distance              % 2,079.8, 21, 1,029.8 for seed 1
```

The main comparison, five operators over five seeds at twenty seconds each:

```matlab
run_day(20, 1:5, 6, 1200)
```

The ablations and sensitivities of Section 4.3:

```matlab
exp_ablation(1:5, 20, 6, 1200)          % context removed, single arm
run_budget([5 10 20 40], 1:3, 6, 1200)  % objective against the budget
```

The Chapter 3 benchmarks are in `matlab/ch3_solomon/`; they read their own instance
files through `benchmark_dir`, so they need no configuration.

## Cost

One call at twenty seconds runs about 250 iterations on an AMD Ryzen 7 5800H and takes
twenty five seconds including the construction. The whole experiment suite of Chapter 4
is about one hour of wall clock.

## Data

The road network is derived from OpenStreetMap, which is openly available under the
Open Data Commons Open Database Licence (ODbL). The derived matrices in `data/` are
therefore shared under the same licence, with attribution to OpenStreetMap
contributors. The demand figures are synthetic and were set to reproduce the order of
magnitude of a district parcel network.

`data/case.mat` is 51 MB. It is kept in the repository so the code runs out of the box;
a copy also sits with the archived release on Zenodo.

## Licence

Code: MIT, see `LICENSE`.
Derived network data: ODbL 1.0.

## Citation

See `CITATION.cff`. The archived release carries a DOI once the repository is connected
to Zenodo.