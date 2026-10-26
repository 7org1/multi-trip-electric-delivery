"""Map the constructed Lishui case: depot, town stations and village points.

The coordinates are real OSM place nodes; the sizes encode the constructed
demand.  The figure is the check that the geography is sane before any routing
is attempted, and it doubles as a Chapter 4 figure.
"""
import json, os, math, csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.lines import Line2D
from matplotlib.ticker import FuncFormatter

plt.rcParams["font.family"] = "serif"
plt.rcParams["font.serif"] = ["Times New Roman", "DejaVu Serif"]
plt.rcParams["axes.unicode_minus"] = False

BASE = r"C:\Users\YJZT\Desktop\route\build\osm"


def load_roads():
    d = json.load(open(os.path.join(BASE, "lishui.json"), encoding="utf-8"))
    nodes, ways = {}, []
    for e in d["elements"]:
        if e["type"] == "node":
            nodes[e["id"]] = (e["lon"], e["lat"])
        elif e["type"] == "way" and e.get("tags", {}).get("highway"):
            ways.append(e["nodes"])
    segs = []
    for nd in ways:
        pts = [nodes[n] for n in nd if n in nodes]
        segs += [(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
    print("roads:", len(segs), "segments from", len(ways), "ways")
    return segs


def load_boundary():
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


def main():
    roads = load_roads()
    bnd = load_boundary()

    rows = list(csv.DictReader(open(os.path.join(BASE, "lishui_points.csv"), encoding="utf-8")))
    hub = [r for r in rows if r["kind"] == "hub"][0]
    towns = [r for r in rows if r["kind"] == "town"]
    vill = [r for r in rows if r["kind"] == "village"]

    fig, ax = plt.subplots(figsize=(11, 11))
    ax.add_collection(LineCollection(roads, colors="0.62", linewidths=0.55, zorder=1))
    ax.add_collection(LineCollection(bnd, colors="0.10", linewidths=2.2, zorder=2))

    lons = [float(r["lon"]) for r in rows]
    lats = [float(r["lat"]) for r in rows]

    allp = towns + vill
    ax.scatter([float(r["lon"]) for r in allp], [float(r["lat"]) for r in allp],
               s=17, c="0.10", edgecolors="white", linewidths=0.35, zorder=5)
    ax.plot(float(hub["lon"]), float(hub["lat"]), marker="*", ms=22,
            mfc="black", mec="white", mew=1.2, zorder=6)

    ax.annotate("Depot", (float(hub["lon"]), float(hub["lat"])),
                xytext=(12, 12), textcoords="offset points", fontsize=9,
                bbox=dict(boxstyle="round,pad=0.3", fc="white", ec="0.4", alpha=0.95), zorder=7)

    pad = 0.03
    ax.set_xlim(min(lons) - pad, max(lons) + pad)
    ax.set_ylim(min(lats) - pad, max(lats) + pad)
    ax.set_aspect(1.0 / math.cos(math.radians(sum(lats) / len(lats))))
    fmt = FuncFormatter(lambda v, p: f"{v:.2f}")
    ax.xaxis.set_major_formatter(fmt); ax.yaxis.set_major_formatter(fmt)
    ax.set_xlabel("Longitude (°E)", fontsize=11)
    ax.set_ylabel("Latitude (°N)", fontsize=11)
    for s in ax.spines.values():
        s.set_linewidth(0.8)

    handles = [
        Line2D([0], [0], marker="*", ls="", ms=15, mfc="black", mec="white", label="Depot"),
        Line2D([0], [0], marker="o", ls="", ms=6, mfc="0.10", mec="white", mew=0.4,
               label=f"Delivery point ({len(towns) + len(vill)})"),
    ]
    ax.legend(handles=handles, loc="lower left", fontsize=9, framealpha=0.95, edgecolor="0.6")

    kl = 111.32 * math.cos(math.radians(sum(lats) / len(lats)))
    x0 = min(lons) + 0.04 * (max(lons) - min(lons))
    y0 = min(lats) + 0.05 * (max(lats) - min(lats))
    ax.plot([x0, x0 + 10 / kl], [y0, y0], color="k", lw=3.5, solid_capstyle="butt", zorder=9)
    ax.text(x0 + 5 / kl, y0 + 0.008, "10 km", ha="center", fontsize=10)

    fig.tight_layout()
    out = os.path.join(BASE, "lishui_case_map.png")
    fig.savefig(out, dpi=300, facecolor="white")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    main()
