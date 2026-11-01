# pmux-optimization

> 第 10 届 FPGA 创新设计竞赛 · 赛题二「多路选择器 PMUX 结构优化」
> 作品：**信号星河：PMUX 通路择**
> 面向 Yosys 综合流程的多路选择器（PMUX/MUX）与算术网络面积优化

## 一、项目简介

在开源综合工具 **Yosys 0.69** 源码树中实现了一个**静态编译进主程序**的自定义 C++ 优化 pass（命令名 `pmux_opt`，非 plugin 动态加载），并在 `synth_intel` 流程内部显式调用。基线版与优化版使用同一条综合命令、同一套脚本，对照差异仅体现在综合器二进制本身。

方案由三层通用、保守、可证明等价的优化手段构成：

1. **R1 · 同构布尔分支公共操作数提出（`pmux_opt`）**：在选择器尚未被技术映射展开前遍历高层网表；当一个 `$pmux` / `$mux` 的各分支由同型、等宽、无符号的二元布尔单元（仅 `$xor` / `$and` / `$or`）驱动并共享同一公共操作数 C 时，依据布尔分配律 `MUX(P_i op C) ≡ MUX(P_i) op C`，把 C 提出到选择器输出级，消除分支中重复的同类单元；不满足全部安全条件即原样保留。
2. **路线 D · 宽位宽 ALU 行波进位**：改写 Cyclone IV 算术技术映射，宽度 `Y_WIDTH ≥ 6` 的加减单元改用逐位全加器行波进位，宽度 `< 6` 回退通用前缀树；进位端口契约保持不变，只改变进位网络结构、不改变逻辑。
3. **b4 · 保守 abc9 内置脚本**：在默认 AIG 精简链中统一插入 `&resub; &fraig; &sweep;`；脚本 9 例统一，不按网表结构切换，未使用激进综合命令。

## 二、目录结构

```
pmux-optimization/
├── code/                 # 工程主体：改动源码、脚本、用例、EQY、综合日志、结果与工程说明
│   ├── src/              # 本次改动源码 + 干净源码对照 unified diff
│   ├── scripts/          # 两臂综合对比 / 单例综合 / 效率测量 / 打补丁 / 一键构建脚本
│   ├── cases/           # 9 个测试用例 Verilog
│   ├── eqy/              # EQY 形式等价验证脚本、9 例证明日志、网表快照与汇总报告
│   ├── logs/             # 两臂综合与效率原始日志
│   ├── compare_result.txt
│   ├── efficiency_result.txt
│   └── README.md         # 构建环境、目录、复现步骤与改动清单（工程详细说明）
├── docs/                 # 技术文档 PDF
├── figures/             # 技术文档配图（流程、改动、ALU 决策、EQY 流程、LUT 对比等）
└── .gitignore
```

> **关于 `code/bin/`**：两臂 WSL/Linux 编译产物（`yosys`、`yosys-abc`、`share/` 数据文件）属于构建生成物，**未纳入本仓库**。按 `code/README.md` 第 5 节的 `build_yosys.sh` / `apply_patches.sh`，可从一份干净的 Yosys 0.69 源码树一键复现基线臂与优化臂。

## 三、环境与版本（两臂严格统一）

| 项目 | 取值 |
|---|---|
| Yosys 版本 | **0.69**，git commit `9f75ca1f9`（tag v0.69 上游源码） |
| ABC 子模块 | commit `a51bf4a7bb38ce06ea3a544b1463b40832213917`（yosys 内置 abc9，未更换、未使用外部 abc） |
| 编译器 / 配置 | g++ 15.2.0，CMake Release；关闭 TCL / readline / editline / zlib / libffi / slang / python / 单元测试，内置 abc 启用 |
| 综合命令 | 两臂逐字相同：`hierarchy -check -top <top>; synth_intel -family cycloneiv; stat` |
| 统计口径 | LUT = `cycloneiv_lcell_comb`（含取反单元）；FF = `dffeas` |

## 四、实测结果（自编译 0.69 两臂，`synth_intel -family cycloneiv`）

### 4.1 面积（`code/compare_result.txt`）

| 指标 | 基线 | 优化后 | 变化 |
|---|---:|---:|---:|
| LUT 合计 | 2422 | 2339 | 总量 **−3.43%**；逐例算术平均 **−2.52%**（n=9） |
| FF 合计 | 323 | 323 | 持平 |

9 例 LUT 全部不反增、FF 全部不增加；各例 `check` 0 problems，abc9 `&verify` 全部等价。

### 4.2 形式等价（`code/eqy/`）

EQY 在 abc9 打包之后、专用单元映射之前的 `$lut` + 标准化内部触发器网表上做分区 SAT 证明：**9 / 9 例 `DONE (PASS, rc=0)`，共 345 个分区等价**；两臂触发器逐例完全一致。

### 4.3 效率（`code/efficiency_result.txt`，5 次平均）

- 综合时间合计比值 **1.048**，主进程峰值内存合计比值 **0.998**，均在 1.05 阈值内。
- 阈值口径：比值 ≤ 1.05 满分；> 1.05 警告；> 1.15 该例该项不得分（时间 / 内存任一越线即判）。
- 三例时间比处于 1.05–1.15 警告区（case03 1.077、case04 1.085、case05 1.055），均未越过 1.15；9 例内存比全部 ≤ 1.05。

## 五、快速复现

工程详细说明、脚本参数与从源码复现两臂的完整步骤见 **[`code/README.md`](code/README.md)**。

在 WSL / Linux 终端进入 `code/` 目录：

```bash
chmod +x scripts/*.sh

# 两臂 9 例批量面积对比
bash scripts/compare_baseline.sh

# 两臂运行时间 / 峰值内存对比（默认 5 次平均）
bash scripts/measure_efficiency.sh

# EQY 形式等价验证（需 eqy 在 PATH）
bash eqy/scripts/export_eqy_all.sh
bash eqy/scripts/run_eqy_all.sh
bash eqy/scripts/finalize_eqy_report.sh
```

从干净 0.69 源码树构建两臂的步骤见 `code/README.md` 第 5 节。

## 六、文档与配图

- 技术文档：[`docs/技术文档_信号星河_PMUX通路择.pdf`](docs/技术文档_信号星河_PMUX通路择.pdf)
- 配图目录：[`figures/`](figures/)
