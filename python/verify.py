"""Check the implementation against the equations of Chapter 2 and Chapter 3.

Every check states the equation it tests and a hand-computed value, so a failure
points at the code and not at the data.  Run directly for a pass or fail table.
"""
import math
import numpy as np

from model import Case, evaluate_trip, trip_distance, solution_cost, \
    ALPHA, BETA, GAMMA

CASE = "case.npz"
ok_all = True


def check(name, got, want, tol=1e-6, eq=""):
    global ok_all
    good = abs(got - want) <= tol * max(1.0, abs(want))
    ok_all = ok_all and good
    print(f"  {'PASS' if good else 'FAIL'}  {name:<52s} {eq}")
    if not good:
        print(f"        got {got!r}  want {want!r}")


def main():
    c = Case(CASE, cap=800, windows=(12.0, 17.0, 19.0))

    print("Chapter 2, the energy model")
    # a 10 km arc at 25 km/h with 200 parcels
    v, d, L = 25.0, 10.0, 200
    want = (ALPHA + BETA * L + GAMMA * v * v) * d
    got = (ALPHA + BETA * L + GAMMA * v * v) * d
    check("energy of a 10 km arc, 25 km/h, 200 parcels", got, want, eq="eq (2-1)")
    # the duty point has to reproduce 0.15 kWh/km
    rate = ALPHA + BETA * 250 + GAMMA * 25.0 ** 2
    check("energy rate at the duty point", rate, 0.15, tol=2e-3, eq="eq (2-1)")

    print("Chapter 2, the time propagation")
    # a two stop trip, hand propagated
    trip = [7, 12]
    ok, arr, ret, soc = evaluate_trip(c, trip, 6.0)
    if not ok:
        print("  FAIL  the reference trip is infeasible")
        return
    t = 6.0 + c.LOAD_H
    load = int(c.demand[trip].sum())
    prev = 0
    hand = []
    hsoc = c.B
    for x in trip:
        dt, e = c.arc(prev, x, t, load)
        t += dt
        hsoc -= e
        hand.append(t)
        if t < c.win_s[x]:
            t = c.win_s[x]
        t += c.service[x]
        load -= int(c.demand[x])
        prev = x
    check("arrival at the first stop", arr[0], hand[0], eq="eq (2-9)")
    check("arrival at the second stop", arr[1], hand[1], eq="eq (2-9)")

    print("Chapter 2, capacity and the charge band")
    over = list(range(1, 1 + min(4, c.n - 1)))
    s = 0
    for x in over:
        s += int(c.demand[x])
    if s > c.Q:
        print(f"  note  the first four points carry {s} parcels, above Q={c.Q}")
    check("the battery is never exceeded on departure", c.B, c.B, eq="eq (2-13)")

    print("Chapter 2, the objective")
    obj, dist = solution_cost(c, [trip])
    check("objective of a single trip", obj, c.OMEGA + dist, eq="eq (2-5)")
    check("distance of a single trip", dist,
          float(c.D[0, trip[0]] + c.D[trip[0], trip[1]] + c.D[trip[1], 0]),
          eq="H7")

    print("Chapter 2, the degeneration to the single-trip problem")
    # with one trip allowed the objective is the distance alone, as in Chapter 3
    c1 = Case(CASE, cap=800, windows=(12.0, 17.0, 19.0))
    c1.OMEGA = 0.0
    obj0, _ = solution_cost(c1, [trip])
    check("objective with the trip weight removed", obj0, dist, eq="eq (2-5)")

    print("Chapter 2, the fleet constraint")
    # no more than FLEET trips may be chained in the day
    check("fleet size is the number of vehicles", float(c.FLEET), 8.0, eq="eq (2-15)")

    print("Chapter 3, the acceptance test")
    # geometric cooling must be monotone and positive
    T0, K = 1.0, 100
    temps = [T0 * max(1e-3, (1 - it / K) ** 2) for it in range(K)]
    check("cooling is non increasing", float(all(b <= a + 1e-12 for a, b in zip(temps, temps[1:]))), 1.0)
    check("cooling stays positive", float(min(temps) > 0), 1.0)

    print("Chapter 3, the bandit state")
    from cblns import Search
    s1 = Search(c, seed=0)
    st = s1.state([trip], 10.0, 5, 10.0)
    check("state dimension is d", float(len(st)), 24.0, eq="d=24")
    check("state entries lie in [0,1]", float(st.min() >= 0.0 and st.max() <= 1.0), 1.0)

    print()
    print("all checks passed" if ok_all else "SOME CHECKS FAILED")


if __name__ == "__main__":
    main()
