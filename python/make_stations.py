"""Construct the case instance on the Lishui road network.

Station coordinates come from OpenStreetMap place nodes inside the administrative
polygon.  The instance has one depot, eight town-level stations and ninety-one
village-level points.  Demand, service windows, service times and the vehicle
parameters are design values, set so that the instance is feasible but not
slack; they are listed as parameters in Chapter 4 and are not imported from any
operating record.
"""
import json, os, math, random, csv

BASE = r"C:\Users\YJZT\Desktop\route\build\osm"

DEPOT_NAME = "永阳街道"
N_TOWN = 8
N_VILLAGE = 91
TOTAL_PARCELS = 24000
CAPACITY = 500

VILLAGE_TAGS = ("village", "hamlet")
COMMUNITY_TAGS = ("neighbourhood", "quarter", "locality", "isolated_dwelling")

BORDER_BUFFER_M = 500.0

random.seed(20260422)


def load_polygon():
    d = json.load(open(os.path.join(BASE, "lishui_boundary.json"), encoding="utf-8"))
    segs = []
    for e in d["elements"]:
        if e["type"] != "relation":
            continue
        for m in e.get("members", []):
            g = m.get("geometry")
            if not g:
                continue
            pts = [(p["lon"], p["lat"]) for p in g if "lon" in p and "lat" in p]
            segs += [(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
    return segs


def inside(pt, segs):
    x, y = pt
    n = 0
    for (x1, y1), (x2, y2) in segs:
        if (y1 > y) != (y2 > y):
            if x1 + (y - y1) * (x2 - x1) / (y2 - y1) > x:
                n += 1
    return n % 2 == 1


def hav(a, b):
    R = 6371000.0
    la1, lo1 = math.radians(a[1]), math.radians(a[0])
    la2, lo2 = math.radians(b[1]), math.radians(b[0])
    t = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * R * math.asin(min(1.0, math.sqrt(t)))


def load_places():
    out, seen = [], set()
    for fn in ("lishui_places.json", "lishui_places2.json"):
        p = os.path.join(BASE, fn)
        if not os.path.exists(p):
            continue
        d = json.load(open(p, encoding="utf-8"))
        for e in d["elements"]:
            t = e.get("tags", {})
            key = (e["lon"], e["lat"])
            if key in seen:
                continue
            seen.add(key)
            out.append({"place": t.get("place", ""), "name": (t.get("name") or "").strip(),
                        "lon": e["lon"], "lat": e["lat"]})
    return out


def segdist(p, a, b):
    px, py = p
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def border_m(p, segs):
    """distance from a point to the nearest boundary segment, in metres"""
    d = min(segdist((p["lon"], p["lat"]), a, b) for a, b in segs)
    return d * 111320.0 * math.cos(math.radians(p["lat"]))


def main():
    segs = load_polygon()
    places = [p for p in load_places()
              if inside((p["lon"], p["lat"]), segs) and border_m(p, segs) >= BORDER_BUFFER_M]

    depot = next(p for p in places if p["name"] == DEPOT_NAME)
    rest = [p for p in places if p["name"] != DEPOT_NAME]
    for p in rest:
        p["d"] = hav((p["lon"], p["lat"]), (depot["lon"], depot["lat"]))

    towns = [p for p in rest if p["place"] in ("town", "suburb")]
    towns.sort(key=lambda p: (0 if p["name"].endswith(("街道", "镇")) else 1, p["name"]))
    seen, town_sel = set(), []
    for p in towns:
        stem = p["name"].replace("街道", "").replace("镇", "")
        if not p["name"] or stem in seen:
            continue
        seen.add(stem)
        town_sel.append(p)
    town_sel = town_sel[:N_TOWN]
    town_ids = {id(p) for p in town_sel}

    # candidates for village-level points, excluding the towns already chosen
    used = {(p["lon"], p["lat"]) for p in town_sel} | {(depot["lon"], depot["lat"])}
    pool = [p for p in rest
            if p["place"] in (VILLAGE_TAGS + COMMUNITY_TAGS)
            and (p["lon"], p["lat"]) not in used]

    # stratified selection: one representative per grid cell, then fill the
    # remaining slots at the point farthest from the set already chosen, so that
    # no single cell dominates and the district interior is covered evenly
    CELL = 0.030
    cells = {}
    for p in pool:
        key = (int(p["lon"] / CELL), int(p["lat"] / CELL))
        cells.setdefault(key, []).append(p)
    reps = []
    for key, ps in cells.items():
        cx, cy = (key[0] + 0.5) * CELL, (key[1] + 0.5) * CELL
        reps.append(min(ps, key=lambda q: (q["lon"] - cx) ** 2 + (q["lat"] - cy) ** 2))
    reps.sort(key=lambda p: -p["d"])

    def mind(p, S):
        return min(hav((p["lon"], p["lat"]), (q["lon"], q["lat"])) for q in S)

    village_sel = reps[:N_VILLAGE]
    left = [p for p in pool if p not in village_sel]
    while len(village_sel) < N_VILLAGE and left:
        best = max(left, key=lambda q: mind(q, village_sel))
        village_sel.append(best)
        left.remove(best)

    # de-clutter, then refill: a village point that sits almost on top of a town
    # station adds nothing, so it is dropped and its slot is given to the unused
    # candidate that lies farthest from everything already selected
    MIN_SEP_KM = 0.60

    def km(a, b):
        return hav((a["lon"], a["lat"]), (b["lon"], b["lat"])) / 1000.0

    kept = []
    for p in village_sel:
        if any(km(p, q) < MIN_SEP_KM for q in town_sel):
            continue
        if any(km(p, q) < MIN_SEP_KM for q in kept):
            continue
        kept.append(p)
    dropped = len(village_sel) - len(kept)
    village_sel = kept

    taken = {id(q) for q in town_sel} | {id(q) for q in village_sel}
    spare = [q for q in pool if id(q) not in taken]
    refilled = 0
    while len(village_sel) < N_VILLAGE and spare:
        best = max(spare, key=lambda q: min(km(q, s) for s in town_sel + village_sel))
        village_sel.append(best)
        spare.remove(best)
        refilled += 1
    print(f"de-clutter: dropped {dropped}, refilled {refilled} from the sparse end")

    stations = town_sel + village_sel

    n = len(stations)
    raw = [math.exp(random.gauss(0.0, 0.55)) for _ in range(n)]
    scale = TOTAL_PARCELS / sum(raw)
    for i, p in enumerate(stations):
        w = 1.8 if id(p) in town_ids else 1.0
        p["demand"] = max(15, int(round(raw[i] * scale * w)))
    tot = sum(p["demand"] for p in stations)
    for p in stations:
        p["demand"] = max(15, int(round(p["demand"] * TOTAL_PARCELS / tot)))

    stations.sort(key=lambda p: (0 if id(p) in town_ids else 1, -p["d"]))
    out = os.path.join(BASE, "lishui_stations.csv")
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "kind", "name", "lon", "lat", "demand",
                    "dist_hub_m", "window_start", "window_end", "service_s"])
        w.writerow(["DEPOT", "hub", DEPOT_NAME, f"{depot['lon']:.6f}", f"{depot['lat']:.6f}",
                    0, 0, "06:00", "20:00", 0])
        for k, p in enumerate(stations, 1):
            kind = "town" if id(p) in town_ids else "village"
            dh = p["d"]
            if dh < 5000:
                ws, we = "08:00", "12:00"
            elif dh < 12000:
                ws, we = "09:00", "15:00"
            else:
                ws, we = "09:00", "17:00"
            svc = 120 + 0.6 * p["demand"]
            w.writerow([f"S{k:03d}", kind, p["name"] or f"site{k:03d}",
                        f"{p['lon']:.6f}", f"{p['lat']:.6f}", p["demand"],
                        f"{dh:.0f}", ws, we, f"{svc:.0f}"])

    dem = [p["demand"] for p in stations]
    dd = [p["d"] / 1000 for p in stations]
    trips = -(-sum(dem) // CAPACITY)
    print(f"places inside the polygon {len(places)}; stations {len(stations)} "
          f"(town {len(town_sel)}, village {len(village_sel)})")
    print(f"depot {DEPOT_NAME} {depot['lon']:.5f}, {depot['lat']:.5f}")
    print(f"demand total {sum(dem)}  mean {sum(dem)/len(dem):.0f}  min {min(dem)}  max {max(dem)}")
    print(f"distance {min(dd):.1f} .. {max(dd):.1f} km, mean {sum(dd)/len(dd):.1f}")
    print(f"trips at {CAPACITY}/trip: {trips}")
    print(f"points whose demand exceeds one load: {sum(1 for x in dem if x > CAPACITY)}")
    print("wrote", out)


if __name__ == "__main__":
    main()
