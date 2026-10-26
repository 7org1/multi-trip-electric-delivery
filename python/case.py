"""Build the case matrices from the district graph.

The graph has thirty-one thousand nodes with OSM identifiers that run to eleven
digits, so the adjacency is built on contiguous indices rather than on the
identifiers themselves.

The routing only ever touches the depot and the ninety-nine demand points.  Each
is snapped to its nearest graph node, Dijkstra is run from each, and two matrices
are stored:

    D[i, j]      shortest path distance in kilometres, the arc cost of the model
    T[b, i, j]   travel time in hours along that same path under speed band b

The path is chosen by distance, as H7 requires, so the travel time is that of the
distance-shortest path and not of the fastest path.

Run the module directly to build and cache the matrices as case.npz.
"""
import csv, math, heapq, os
import numpy as np

BASE = r"C:\Users\YJZT\Desktop\route\build\osm"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "case.npz")

SHAPE = [(0, 6, 0.00), (6, 7, 0.25), (7, 9, 1.00), (9, 11, 0.55),
         (11, 13, 0.45), (13, 17, 0.50), (17, 19, 1.05), (19, 22, 0.35),
         (22, 24, 0.00)]
BANDS = [(0, 6), (6, 7), (7, 9), (9, 11), (11, 13), (13, 17), (17, 19),
         (19, 22), (22, 24)]
REP_HOUR = [3.0, 6.5, 8.0, 10.0, 12.0, 15.0, 18.0, 20.5, 23.0]

BAND_AMP = [(0, 4, 0.62), (4, 12, 0.38), (12, 999, 0.18)]
CLASS = {"motorway": 1.15, "motorway_link": 1.1, "trunk": 1.15, "trunk_link": 1.1,
         "primary": 1.15, "primary_link": 1.1, "secondary": 1.0, "secondary_link": 1.0,
         "tertiary": 0.85, "tertiary_link": 0.85, "unclassified": 0.8,
         "residential": 0.75, "living_street": 0.7, "service": 0.7}


def load_nodes():
    ids, coords = [], []
    with open(os.path.join(BASE, "district_nodes.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            ids.append(int(r["node_id"]))
            coords.append((float(r["lon"]), float(r["lat"])))
    return ids, np.array(coords)


def load_edges():
    rows = []
    with open(os.path.join(BASE, "district_edges.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            rows.append((int(r["u"]), int(r["v"]), float(r["length_m"]) / 1000.0,
                         float(r["limit_kmh"]), r["highway"]))
    return rows


def load_stations():
    rows = []
    with open(os.path.join(BASE, "lishui_points.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            rows.append({"id": r["id"], "kind": r["kind"], "name": r["name"],
                         "lon": float(r["lon"]), "lat": float(r["lat"]),
                         "demand": int(r["demand"]),
                         "win_s": r["window_start"], "win_e": r["window_end"],
                         "service_s": float(r["service_s"])})
    depot = [r for r in rows if r["kind"] == "hub"][0]
    stops = [r for r in rows if r["kind"] != "hub"]
    return depot, stops


def amplitude(d_km, hw):
    a = 0.18
    for lo, hi, v in BAND_AMP:
        if lo <= d_km < hi:
            a = v
            break
    return max(0.05, min(0.70, a * CLASS.get(hw, 0.8)))


def shape(h):
    h = h % 24
    for a, b, v in SHAPE:
        if a <= h < b:
            return v
    return 0.0


def build():
    ids, coords = load_nodes()
    index = {nid: i for i, nid in enumerate(ids)}
    N = len(ids)
    print(f"graph: {N} nodes")

    depot, stops = load_stations()
    pts = [depot] + stops
    n = len(pts)

    # snap each point to its nearest graph node, vectorised
    lat = coords[:, 1]
    kmlon = 111.32 * np.cos(np.radians(lat))
    snap, snap_d = [], []
    for p in pts:
        dx = (coords[:, 0] - p["lon"]) * kmlon
        dy = (coords[:, 1] - p["lat"]) * 110.57
        d = np.hypot(dx, dy)
        j = int(np.argmin(d))
        snap.append(j)
        snap_d.append(d[j] * 1000.0)
    print(f"snap to the road: median {np.median(snap_d):.0f} m, max {max(snap_d):.0f} m")

    ddep = np.hypot((coords[:, 0] - depot["lon"]) * kmlon,
                    (coords[:, 1] - depot["lat"]) * 110.57)

    adj = [[] for _ in range(N)]
    for u, v, L, lim, hw in load_edges():
        iu, iv = index[u], index[v]
        ae = amplitude(max(ddep[iu], ddep[iv]), hw)
        adj[iu].append((iv, L, lim, ae))
        adj[iv].append((iu, L, lim, ae))
    print(f"edges: {sum(len(a) for a in adj)} directed arcs")

    # a point must snap to a node that is reachable from the depot, otherwise its
    # distance is infinite and no trip can ever serve it
    dist0 = {snap[0]: 0.0}
    pq = [(0.0, snap[0])]
    while pq:
        du, u = heapq.heappop(pq)
        if du > dist0.get(u, 1e18):
            continue
        for v_, L_, lim_, ae_ in adj[u]:
            nd = du + L_
            if nd < dist0.get(v_, 1e18):
                dist0[v_] = nd
                heapq.heappush(pq, (nd, v_))
    reach = np.array(sorted(dist0.keys()))
    fixed = 0
    for i in range(n):
        if snap[i] in dist0:
            continue
        coords_r = coords[reach]
        dx = (coords_r[:, 0] - pts[i]["lon"]) * kmlon[reach]
        dy = (coords_r[:, 1] - pts[i]["lat"]) * 110.57
        dd = np.hypot(dx, dy)
        k = int(np.argmin(dd))
        snap[i] = int(reach[k])
        snap_d[i] = dd[k] * 1000.0
        fixed += 1
    if fixed:
        print(f"re-snapped {fixed} points onto the reachable part of the graph")

    svals = [shape(h) for h in REP_HOUR]
    D = np.full((n, n), np.inf)
    T = np.zeros((len(BANDS), n, n))
    PR = np.full((n, N), -1, dtype=np.int64)

    for s in range(n):
        src = snap[s]
        dist = {src: 0.0}
        prev = {}
        pq = [(0.0, src)]
        while pq:
            du, u = heapq.heappop(pq)
            if du > dist.get(u, 1e18):
                continue
            for v, L, lim, ae in adj[u]:
                nd = du + L
                if nd < dist.get(v, 1e18):
                    dist[v] = nd
                    prev[v] = (u, L, lim, ae)
                    heapq.heappush(pq, (nd, v))
        for v, (pu, L, lim, ae) in prev.items():
            PR[s, v] = pu
        for t in range(n):
            if t == s:
                continue
            dst = snap[t]
            if dst not in dist:
                continue
            D[s, t] = dist[dst]
            chain = []
            cur = dst
            while cur != src:
                pu, L, lim, ae = prev[cur]
                chain.append((L, lim, ae))
                cur = pu
            for b in range(len(BANDS)):
                sv = svals[b]
                tot = 0.0
                for L, lim, ae in chain:
                    m = 1.0 - ae * sv
                    if m < 0.15:
                        m = 0.15
                    tot += L / (lim * m)
                T[b, s, t] = tot

    np.savez_compressed(
        OUT, D=D, T=T, PR=PR,
        lon=np.array([p["lon"] for p in pts]),
        lat=np.array([p["lat"] for p in pts]),
        demand=np.array([p["demand"] for p in pts], dtype=int),
        service=np.array([p["service_s"] for p in pts], dtype=float),
        win_s=np.array([p["win_s"] for p in pts]),
        win_e=np.array([p["win_e"] for p in pts]),
        kind=np.array([p["kind"] for p in pts]),
        name=np.array([p["name"] for p in pts]),
        snap=np.array(snap, dtype=np.int64),
        node_index=np.array([ids[j] for j in snap], dtype=np.int64))
    print(f"wrote {OUT}")
    fin = D[D < np.inf]
    print(f"distance: median {np.median(fin):.1f} km, max {fin.max():.1f} km")
    for b in (2, 5, 6):
        tt = T[b][T[b] > 0]
        print(f"  band {BANDS[b][0]:02d}:00-{BANDS[b][1]:02d}:00  median "
              f"{60*np.median(tt):.0f} min, max {60*tt.max():.0f} min")


if __name__ == "__main__":
    build()
