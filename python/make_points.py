"""Split each demand station into delivery points so that the total is exact.

Two points per station, and the stations with the largest demand get a third, so that
the case lands on TARGET points while its daily volume is unchanged.  The purpose is
to reach the scale of the extended Solomon instances, where a route holds ten to
twenty five stops; with one point per station a route would hold three.
"""
import csv, math, os

BASE = r"C:\Users\YJZT\Desktop\route\build\osm"
SRC = os.path.join(BASE, "lishui_stations.csv")
DST = os.path.join(BASE, "lishui_points.csv")
TARGET = 200
R_M = 350.0
DLAT = R_M / 110_574.0


def main():
    rows = list(csv.DictReader(open(SRC, encoding="utf-8")))
    depot = [r for r in rows if r["kind"] == "hub"][0]
    stops = [r for r in rows if r["kind"] != "hub"]

    kk = [2] * len(stops)
    extra = TARGET - 2 * len(stops)
    if extra > 0:
        order = sorted(range(len(stops)), key=lambda i: -int(stops[i]["demand"]))
        for i in order[:extra]:
            kk[i] += 1
    elif extra < 0:
        order = sorted(range(len(stops)), key=lambda i: int(stops[i]["demand"]))
        for i in order[:-extra]:
            kk[i] = 1

    out = [depot]
    k = 0
    for r, K in zip(stops, kk):
        k += 1
        d = int(r["demand"])
        parts = [d // K] * K
        parts[0] += d - sum(parts)
        for j in range(K):
            ang = math.radians(k * 137.5 + j * 360.0 / K)
            dlon = DLAT / max(0.2, math.cos(math.radians(float(r["lat"]))))
            lon = float(r["lon"]) + math.cos(ang) * dlon
            lat = float(r["lat"]) + math.sin(ang) * DLAT
            out.append({
                "id": "P%03d%d" % (k, j),
                "kind": r["kind"],
                "name": "%s-%d" % (r["name"], j + 1),
                "lon": "%.7f" % lon,
                "lat": "%.7f" % lat,
                "demand": parts[j],
                "dist_hub_m": r["dist_hub_m"],
                "window_start": r["window_start"],
                "window_end": r["window_end"],
                "service_s": "%.1f" % (120 + 0.6 * parts[j]),
            })

    with open(DST, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)

    n = len(out) - 1
    dem = sum(int(r["demand"]) for r in out if r["kind"] != "hub")
    vals = sorted(int(r["demand"]) for r in out if r["kind"] != "hub")
    print(f"wrote {DST}: {n} delivery points, total {dem}, mean {dem/n:.0f}, "
          f"median {vals[n//2]}, range {vals[0]}..{vals[-1]}")


if __name__ == "__main__":
    main()
