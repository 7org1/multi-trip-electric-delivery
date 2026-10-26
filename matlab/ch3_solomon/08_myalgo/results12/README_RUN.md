# results12 — 六种调度器 × 12 算例 × 5 种子的完整对照

本目录由 `run_12.m` 生成，看门狗 `watchdog2.ps1` 按阶段串联。  
所有数字都是 **300 秒 CPU 时间**（`cpu_budget` 用 `cputime`，不是墙钟）。

---

## 一、六个模式

| mode | 调度器 | 信息使用 | 用途 |
|---|---|---|---|
| `roundrobin` | 均匀轮转 | 无 | **消融下界** |
| `adaptive` | 指数平滑权重（Ropke & Pisinger 形式） | 算子平均收益 | **无状态学习基线** |
| `linucb` | 线性 UCB，常数 α=0.5 | 状态 + 收益 | 有状态学习 |
| `pure` | 固定一个算子（`pureArm=2`） | 无 | **零信息对照：学习是否退化成一个常数** |
| `thompson` | 线性 Thompson 采样 | 状态 + 后验不确定性 | 无参数探索 |
| `linucb-sched` | 线性 UCB，α_t = sqrt(d·ln(1+t/δ)) | 状态 + 收益 | 理论给定调度，保持确定性 |

`pure` / `thompson` / `linucb-sched` 运行在 `solve_rlgbka_v2.m`，其余运行在
`solve_rlgbka_online.m`。**v2 是原文件逐行复制的副本**，已用 `Compare-Object` 验证
差异只有「函数名、两个新选项、三个新模式」，没有其他改动。

---

## 二、算子与臂的对应关系（容易搞错）

```
opSet = [3 5 2]
    arm 1 → 算子 3 → 扇区移除（极角连续切片）
    arm 2 → 算子 5 → 随机移除            ← pure 模式固定用这个
    arm 3 → 算子 2 → 最差移除（距离节省排序）
```

实测贡献（早期 300 秒轮转运行）：随机 417 次改进、扇区 140、最差 86。

---

## 三、公共参数

| 参数 | 值 | 说明 |
|---|---|---|
| 预算 | 300 s CPU | `cpu_budget` |
| 种子 | 1–5 | |
| 车重 | 10,000 | 目标 = 距离 + 10⁴ × 车数 |
| 接受准则 | 可行-only，T = 0.002·距离·(1−进度)² | `pInfeasible = 0` |
| 罚系数 | 固定 cap=50, tw=5 | 不退火 |
| 自适应权重 | L=100, ρ=0.1, σ=[33 9 13 0] | 文献默认值，未调 |
| LinUCB | α=0.5；sched 版 α_t=sqrt(24·ln(1+t/0.05)) | |
| 修复 | `vrp_repair_greedy`（09_solvers） | 两级筛选未启用（会牺牲可行性） |

---

## 四、确定性

`solve_rlgbka_online.m` 的退火进度原先读 `ctr.elapsed()`（CPU 秒），机器负载一变轨迹
就分叉 —— 同一配置重跑得到过 22/5377 和 22/5590。现已改为按迭代数：
`frac = 1 − nIter / nIterExpected`（nIterExpected = 20000）。

`merge_12` 会显式检查「同一 (mode, instance, seed) 是否出现冲突结果」，并在
`merged_per_seed.csv` 旁边报告。**如果这一项不是 0，所有方差都不可用。**

---

## 五、文件

```
{roundrobin,adaptive,linucb,pure,thompson,linucb-sched}_part{1,2,3}.csv
    列：instance,mode,seed,veh,dist,gap,feasible,iters,wins,wall
    每文件 20 行（4 算例 × 5 种子）

merged_per_seed.csv     全部行合并
merged_summary.csv      每个 (mode, instance) 的均值/标准差/达标数
watchdog2.log           看门狗日志，含每阶段完成情况和最终是否关机
```

## 六、12 个算例

```
part1: c1_2_1  c1_2_4  c2_2_1  c2_2_4
part2: r1_2_1  r1_2_4  r2_2_1  r2_2_4
part3: rc1_2_1 rc1_2_4 rc2_2_1 rc2_2_4
```
