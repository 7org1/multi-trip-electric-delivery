import re, os

M = r"C:\Users\YJZT\Desktop\route\build\exp\matlab"

# 1) 新增 s_of_band：每一档速度带的拥堵水平 s
s_file = os.path.join(M, "ch2_model", "s_of_band.m")
open(s_file, "w", encoding="utf-8").write('''function s = s_of_band(k)
% S_OF_BAND  Congestion level s(t) that belongs to speed band k.
%
%   The shape of the day, from Table 2 of the paper.  Band k covers the k-th row of
%   C.BANDS, which is the interval [0 6), [6 7), [7 9), ... of the day.

S = [0.00; 0.25; 1.00; 0.55; 0.45; 0.50; 1.05; 0.35; 0.00];
s = S(min(max(k, 1), numel(S)));
end
''')
print("wrote s_of_band.m")

# 2) congestion.m 增加第三个输出 mu，即按行驶时间加权的平均拥堵水平
p = os.path.join(M, "ch2_model", "congestion.m")
c = open(p, encoding="utf-8").read()
c = c.replace("function [share, dom] = congestion(C, trip, depart)",
              "function [share, dom, mu] = congestion(C, trip, depart)")
c = c.replace("acc = zeros(1, 3);\ntotal = 0;", "acc = zeros(1, 3);\ntotal = 0;\nwsum = 0;")
c = c.replace("""    total = total + dt;
    g = congestion_band(C, t);""", """    total = total + dt;
    wsum = wsum + dt * s_of_band(b);
    g = congestion_band(C, t);""")
c = c.replace("""total = total + dt;
g = congestion_band(C, t);
acc(g) = acc(g) + dt;

if total > 0
    share = acc / total;
else
    share = [0 0 0];
end""", """total = total + dt;
wsum = wsum + dt * s_of_band(b);
g = congestion_band(C, t);
acc(g) = acc(g) + dt;

if total > 0
    share = acc / total;
    mu = wsum / total;
else
    share = [0 0 0];
    mu = 0;
end""")
c = c.replace("%     dom    the regime taking most of the driving time",
              "%     dom    the regime taking most of the driving time\n"
              "%     mu     mean congestion level, weighted by the time spent on each arc")
open(p, "w", encoding="utf-8", newline="\n").write(c)
print("patched congestion.m")

# 3) solve_day：构造后算三分位切点，pick_band 按平均拥堵水平分档
p = os.path.join(M, "ch4_lishui", "solve_day.m")
c = open(p, encoding="utf-8").read()

anchor = "t0 = tic; it = 0; sinceBest = 0; bandMix = band_mix(C, routes);"
add = anchor + """
% tercile cut points of the mean congestion level over the trips of the construction,
% so that the three regimes hold about a third of the trips each
MU = [];
for vv = 1:numel(routes)
    [okv, ~, ~, ~, ~, dp, ~] = route_eval(C, routes{vv}, C.TSTART, C.B);
    if ~okv, continue, end
    for kk = 1:min(numel(routes{vv}), numel(dp))
        [~, ~, mv] = congestion(C, routes{vv}{kk}, dp(kk));
        MU(end+1) = mv;
    end
end
if numel(MU) >= 3
    MU = sort(MU);
    cut1 = MU(max(1, round(numel(MU) / 3)));
    cut2 = MU(max(1, round(2 * numel(MU) / 3)));
else
    cut1 = 0.4; cut2 = 0.8;
end"""
c = c.replace(anchor, add)

c = c.replace("[g, clk] = pick_band(C, routes, allV, allK, allC);",
              "[g, clk] = pick_band(C, routes, allV, allK, allC, cut1, cut2);")
c = c.replace("function [g, clk] = pick_band(C, routes, allV, allK, allC)",
              "function [g, clk] = pick_band(C, routes, allV, allK, allC, cut1, cut2)")
c = c.replace("    [~, dom] = congestion(C, routes{v}{k}, dep(k));",
              "    [~, ~, mv] = congestion(C, routes{v}{k}, dep(k));\n"
              "        dom = 1 + (mv >= cut1) + (mv >= cut2);")
open(p, "w", encoding="utf-8", newline="\n").write(c)
print("patched solve_day.m")
