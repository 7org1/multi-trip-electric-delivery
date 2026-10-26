import re, os, sys

P = r"C:\Users\YJZT\Desktop\route\build\exp\matlab\ch4_lishui\solve_day.m"
c = open(P, encoding="utf-8").read()

# 1) 增加两个可选参数：是否使用拥堵上下文、只允许某个算子
m = re.search(r"function\s+\[([^\]]*)\]\s*=\s*solve_day\(([^)]*)\)", c)
if not m:
    print("signature not found"); sys.exit(1)
outs, args = m.group(1), m.group(2)
if "useCong" not in args:
    new_sig = f"function [{outs}] = solve_day({args}, useCong, onlyArm)"
    c = c[:m.start()] + new_sig + c[m.end():]

# 2) 默认值
anchor = "if nargin < 1"
idx = c.find(anchor)
if idx < 0:
    # 没有 nargin 检查时，插在函数体第一行之后
    body = c.find("\n", c.find(")", c.find("function")))+1
    c = c[:body] + "if nargin < 6 || isempty(useCong), useCong = true; end\n" \
                   "if nargin < 7 || isempty(onlyArm), onlyArm = 0; end\n" + c[body:]
else:
    c = c[:idx] + ("if nargin < 6 || isempty(useCong), useCong = true; end\n"
                   "if nargin < 7 || isempty(onlyArm), onlyArm = 0; end\n") + c[idx:]

# 3) 关掉拥堵上下文时，状态里的三维恒为零，档位恒为一
c = c.replace("t0 = tic; it = 0; sinceBest = 0; bandMix = band_mix(C, routes);",
              "t0 = tic; it = 0; sinceBest = 0;\n"
              "if useCong, bandMix = band_mix(C, routes); else, bandMix = zeros(3,1); end")
c = c.replace("if mod(it, 20) == 1, bandMix = band_mix(C, routes); end",
              "if useCong && mod(it, 20) == 1, bandMix = band_mix(C, routes); end")
c = c.replace("[g, clk] = pick_band(C, routes, allV, allK, allC, cut1, cut2);",
              "[g, clk] = pick_band(C, routes, allV, allK, allC, cut1, cut2);\n"
              "    if ~useCong, g = 1; end")

# 4) 只允许一个算子
c = c.replace("    nPick(g, ai) = nPick(g, ai) + 1;",
              "    if onlyArm > 0, ai = onlyArm; end\n"
              "    nPick(g, ai) = nPick(g, ai) + 1;")

open(P, "w", encoding="utf-8", newline="\n").write(c)
print("patched solve_day.m")
print("signature:", re.search(r"function.*solve_day\([^)]*\)", c).group(0))
