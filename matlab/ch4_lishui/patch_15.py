import re, os

M = r"C:\Users\YJZT\Desktop\route\build\exp\matlab"

# --- 1) solve_day: 日志增加第五列，记录当前最优目标值（收敛曲线用）
P = os.path.join(M, "ch4_lishui", "solve_day.m")
c = open(P, encoding="utf-8").read()
c = c.replace("logArr = zeros(20000, 4);", "logArr = zeros(20000, 5);")
c = c.replace("logArr(it, :) = [it, clk, ai, g];", "logArr(it, :) = [it, clk, ai, g, bestF];")
open(P, "w", encoding="utf-8", newline="\n").write(c)
print("solve_day patched: log now has 5 columns")

# --- 2) exp_15_19: 用简单的电量轨迹（每趟结束时的电量）替换原函数
P2 = os.path.join(M, "ch4_lishui", "exp_15_19.m")
c2 = open(P2, encoding="utf-8").read()
i = c2.find("function [t, soc] = soc_trace(C, tripList)")
if i < 0:
    print("soc_trace not found"); raise SystemExit
new_fn = '''function [t, soc] = soc_trace(C, tripList)
% charge and time at the end of every trip of one vehicle, read from route_eval
[ok, ~, ~, ~, socEnd, dep, ret] = route_eval(C, tripList, C.TSTART, C.B);
t = []; soc = [];
if ~ok, return, end
for k = 1:numel(ret)
    t(end+1) = dep(k);   soc(end+1) = NaN;   %#ok<AGROW>
    t(end+1) = ret(k);   soc(end+1) = socEnd(k); %#ok<AGROW>
    if k < numel(ret) && dep(k+1) > ret(k)
        t(end+1) = dep(k+1); soc(end+1) = socEnd(k); %#ok<AGROW>
    end
end
if numel(t) >= 2
    v = soc(2:end);
    v = v(~isnan(v));
    if ~isempty(v)
        soc(1) = v(1);
    end
end
soc = fillmissing(soc, 'previous');
soc(isnan(soc)) = C.B;
end
'''
c2 = c2[:i] + new_fn
open(P2, "w", encoding="utf-8", newline="\n").write(c2)
print("soc_trace replaced")
