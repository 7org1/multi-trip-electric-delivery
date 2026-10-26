# Data and code availability

## Statement for the manuscript

The MATLAB code, the case matrices and the result tables that support the findings of
this study are openly available in the repository recorded on Zenodo at
https://doi.org/[DOI TO BE INSERTED].

## Attribution for the derived network data

The road network was derived from OpenStreetMap, which is openly available under the
Open Data Commons Open Database Licence. The derived node table, edge table, distance
matrix, travel time matrices and shortest path tables are shared under the same licence.
Attribution: (c) OpenStreetMap contributors, https://www.openstreetmap.org/copyright

## Files that constitute the data

| File | Content |
|---|---|
| data/case.mat | node coordinates, edge list, distance matrix, nine travel time slices, shortest path tables, boundary segments, point table |
| data/lishui_stations.csv | the 99 service stations before splitting |
| data/lishui_points.csv | the 200 delivery points after splitting |
| results/*.csv | every result table quoted in the paper |

## How the case was built

python/make_stations.py selects the stations and assigns demand;
python/make_points.py splits each station into delivery points;
python/case.py builds the graph, snaps the points, runs the shortest paths and writes
case.mat; python/export_mat.py converts it for MATLAB.