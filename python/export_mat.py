"""Export the case to case.mat so that the solver can run in MATLAB.

Only the data preparation lives here: the graph, the shortest paths and the speed
bands.  The search itself, the scheduling layer and the figures are implemented in
MATLAB under this same folder.

Indices are shifted to one based so that they can be used directly in MATLAB.
"""
import csv, json, os
import numpy as np
from scipy.io import savemat

BASE = r"C:\Users\YJZT\Desktop\route\build\osm"
HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    z = np.load(os.path.join(HERE, "case.npz"), allow_pickle=False)
    D = z["D"]
    T = z["T"]
    n = D.shape[0]

    lon, lat = z["lon"], z["lat"]
    demand = z["demand"].astype(float)
    service = z["service"] / 3600.0
    win_s = np.array([int(s.split(":")[0]) + int(s.split(":")[1]) / 60.0 for s in z["win_s"]])
    win_e = np.array([int(s.split(":")[0]) + int(s.split(":")[1]) / 60.0 for s in z["win_e"]])
    snap = z["snap"].astype(float)
    PR = z["PR"].astype(float)

    # graph coordinates, for drawing the paths
    nlon, nlat = [], []
    with open(os.path.join(BASE, "district_nodes.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            nlon.append(float(r["lon"]))
            nlat.append(float(r["lat"]))

    # boundary segments
    d = json.load(open(os.path.join(BASE, "lishui_boundary.json"), encoding="utf-8"))
    bnd = []
    for e in d["elements"]:
        if e["type"] != "relation":
            continue
        for m in e.get("members", []):
            g = m.get("geometry")
            if not g:
                continue
            pts = [(p["lon"], p["lat"]) for p in g if "lon" in p and "lat" in p]
            for i in range(len(pts) - 1):
                bnd.append([pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]])

    out = {
        "D": D, "Tall": T, "lon": lon, "lat": lat,
        "demand": demand, "serviceH": service,
        "winS": win_s, "winE": win_e,
        "snap": snap + 1.0,                 # one based for MATLAB
        "PR": PR + 1.0,
        "nodeLon": np.array(nlon), "nodeLat": np.array(nlat),
        "bnd": np.array(bnd),
        "nPts": float(n),
    }
    savemat(os.path.join(HERE, "matlab", "case.mat"), out, do_compression=False)
    print(f"wrote case.mat  points {n}  graph nodes {len(nlon)}  boundary segments {len(bnd)}")
    print(f"  D median {np.median(D[D > 0]):.1f} km   demand total {int(demand.sum())}")


if __name__ == "__main__":
    main()
