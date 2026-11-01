# 赛题二「多路选择器 PMUX 结构优化」交付代码说明

> 第 10 届 FPGA 创新设计竞赛 · 赛题二（中科亿海微 / eHiWay 赞助）
> 作品：**信号星河：PMUX 通路择**

本目录包含本次优化的**两臂编译产物、改动源码、综合 / 对比 / 效率脚本、9 个用例与 EQY 等价验证结果**。
所有脚本使用**相对路径**，不写死本机绝对路径；解压后在 WSL / Linux 环境即可复现。

---

## 1. 版本与构建环境（两臂严格统一）

| 项目 | 取值 |
|---|---|
| Yosys 版本 | **0.69**，git commit `9f75ca1f9`（tag v0.69 上游源码） |
| ABC 子模块 | commit `a51bf4a7bb38ce06ea3a544b1463b40832213917`（yosys 内置 abc9，**未更换、未使用外部 abc**） |
| 编译器 / 配置 | g++ 15.2.0，CMake Release；关闭 TCL / readline / editline / zlib / libffi / slang / python / 单元测试，内置 abc 启用 |
| 综合命令 | 两臂逐字相同：`hierarchy -check -top <top>; synth_intel -family cycloneiv; stat` |
| 统计口径 | LUT = `cycloneiv_lcell_comb`（含取反单元）；FF = `dffeas` |
| 产物形态 | 方案 B：WSL / Linux 可执行产物 + 完整源码 + 一键构建脚本（答疑行 88 / 116 允许 WSL 编译产物与现场编译执行） |

**两臂区别只在 yosys 二进制本身**：`bin/original` 为未改动的 pristine 0.69；`bin/optimized` 为内置本次优化 pass 的 0.69。两臂使用同一份源码、同一构建参数编译自比。

---

## 2. 目录结构

```
code/
├── bin/
│   ├── original/                 # 未改动原版 0.69 两臂之一（基线）
│   │   ├── yosys                 #   pristine 可执行程序
│   │   ├── yosys-abc             #   内置 abc 后端（与 yosys 同目录，相对定位）
│   │   └── share/               #   techmap / 单元定义等数据文件
│   └── optimized/               # 优化版（R1 + 路线 D + b4 保守 abc9 脚本）
│       ├── yosys
│       ├── yosys-abc
│       └── share/               # 含路线 D 的 cycloneiv/cells_arith.v
│
├── cases/                        # 9 个测试用例 Verilog（顶层模块名 = 文件名主体）
│   ├── test1.v … test4.v
│   └── pmux_case01_balanced.v … pmux_case05_nested.v
│
├── src/                          # 本次优化改动源码 + 干净源码对照 diff（见第 6 节）
│
├── scripts/                      # 交付版参数化脚本（见第 4 节）
│   ├── compare_baseline.sh       # 两臂 9 例批量综合对比 + 红线校验
│   ├── run_one.sh                # 单例综合封装
│   ├── measure_efficiency.sh     # 两臂运行时间 / 峰值内存（多次平均）测量
│   ├── apply_patches.sh          # 把 src/ 改动安装到一份干净 0.69 源码树（幂等）
│   └── build_yosys.sh            # 从源码树一键构建 pristine / optimized 两臂
│
├── eqy/                          # EQY 形式等价验证脚本、9 例证明日志与汇总报告（见第 7 节）
│
├── compare_result.txt            # 两臂 9 例面积对比结果（由 compare_baseline.sh 生成）
└── logs/                         # 综合 / 效率原始日志（脚本运行后生成）
```

> 运行时 `yosys` 按**可执行文件所在目录**相对定位 `share/` 与 `yosys-abc`，三者必须保持同目录结构；请勿单独移动 `yosys` 二进制。

---

## 3. 快速开始（直接使用随包产物，无需编译）

在 WSL / Linux 终端进入本 `code/` 目录：

```bash
# 0) 脚本加可执行权限（首次）
chmod +x scripts/*.sh

# 1) 两臂 9 例批量对比，输出 LUT / FF / 每例降幅 / 算术平均降幅 / 红线校验
bash scripts/compare_baseline.sh

# 2) 单独综合任一用例（默认使用 optimized 臂）
YOSYS=bin/optimized/yosys bash scripts/run_one.sh pmux_case03_crossbar

# 3) 两臂运行时间 / 峰值内存对比（默认 5 次平均，输出比值与 OK/WARN/FAIL 判定）
bash scripts/measure_efficiency.sh
```

脚本路径与二进制路径均可用环境变量覆盖，例如：

```bash
YOSYS_BASE=/path/to/original/yosys \
YOSYS_OPT=/path/to/optimized/yosys \
CASES_DIR=/path/to/cases \
bash scripts/compare_baseline.sh --out my_compare.txt
```

### 3.1 单条综合命令（评委脚本等价形态）

```bash
bin/optimized/yosys -p "read_verilog cases/pmux_case03_crossbar.v; \
  hierarchy -check -top pmux_case03_crossbar; \
  synth_intel -family cycloneiv; stat"
```

---

## 4. 脚本说明（`code/scripts/`）

| 脚本 | 作用 | 关键环境变量 / 参数 |
|---|---|---|
| `compare_baseline.sh` | 先原版后优化版跑 9 例；抓 `cycloneiv_lcell_comb`、`dffeas`；输出每例 LUT_base / LUT_opt / Δ / 降幅% / FF，总量降幅、**逐例算术平均降幅**；自动校验「每例 LUT 不反增」「FF 不超过基线」；扫描错误日志 | `YOSYS_BASE`、`YOSYS_OPT`、`CASES_DIR`；`--base/--opt/--cases/--out` |
| `run_one.sh` | 单例综合，打印 LUT / FF 与日志路径 | `YOSYS`、`CASES_DIR`；参数 `<用例名> [日志路径]` |
| `measure_efficiency.sh` | `/usr/bin/time -v` 采集墙钟（含 abc 子进程等待）与 yosys 主进程峰值 RSS；预热不计平均；多次（默认 5）取平均；比值 ≤1.05 OK、>1.05 WARN、>1.15 FAIL | `YOSYS_BASE`、`YOSYS_OPT`、`CASES_DIR`、`OUT_FILE`；参数 `<重复次数>` |
| `apply_patches.sh` | 把 `src/` 改动按目标路径复制到干净 0.69 源码树，CMake 登记 `pmux_opt` 幂等追加 | `--src <0.69 源码树目录>` |
| `build_yosys.sh` | CMake 配置（开关与随包产物一致）+ `make -j yosys yosys-abc`；`--mode pristine` 不打补丁，`--mode optimized` 先调 `apply_patches.sh` | `--src`、`--build`、`--mode`、`--jobs` |

---

## 5. 从源码复现构建（可选；随包已含编译产物）

### 5.1 获取干净 0.69 源码

```bash
git clone --branch v0.69 --recursive \
  https://github.com/YosysHQ/yosys.git yosys-0.69
cd yosys-0.69 && git checkout 9f75ca1f9
```

### 5.2 构建原版臂（基线，不打补丁）

```bash
bash code/scripts/build_yosys.sh \
  --src  /path/to/yosys-0.69        \
  --build /path/to/build-original   \
  --mode pristine
```

### 5.3 构建优化版臂

```bash
bash code/scripts/build_yosys.sh \
  --src  /path/to/yosys-0.69        \
  --build /path/to/build-optimized  \
  --mode optimized
```

`--mode optimized` 会先执行 `apply_patches.sh` 安装 `src/` 中的全部改动，再按第 1 节相同 CMake 开关编译。构建产物为 `build/yosys`、`build/yosys-abc`，配套 `share/` 目录位于构建目录内。

> 依赖：g++、cmake、make、python3、bison、flex；本构建关闭了 readline / editline / zlib / libffi / slang / python / 单元测试，仅需基础编译链。

---

## 6. 改动源码清单（`code/src/`）

相对**干净 0.69 源码树**的改动共 5 个文件、1 处 CMake 登记；`*.patch.diff` 为对应干净源码的 unified diff，可直接核对改动范围。

| `src/` 文件 | 源码树目标路径 | 改动说明 |
|---|---|---|
| `pmux_opt.cc` | `passes/opt/pmux_opt.cc` | **新增自定义 C++ pass**，命令名 `pmux_opt`，静态编译进主程序（非 plugin）。实现规则 R1：同构布尔分支公共操作数提出（见 6.1）。 |
| `synth_intel.cc.optimized` | `techlibs/intel/synth_intel.cc` | 仅 **+2 行**：在 `techmap -map +/techmap.v` 之前依次插入 `run("pmux_opt");` 与 `techmap -map +/intel/%s/cells_arith.v`。diff：`synth_intel.cc.patch.diff`。 |
| `cells_arith.v` | `techlibs/intel/cycloneiv/cells_arith.v` | **路线 D**：宽位宽（`Y_WIDTH ≥ 6`）`$alu` 改用逐位行波进位（ripple-carry）；`Y_WIDTH < 6` `_TECHMAP_FAIL_` 回退通用 Brent-Kung 前缀树。diff：`cells_arith.v.patch.diff`。 |
| `abc9.cc` | `passes/techmap/abc9.cc` | 仅内置 `abc9.script.default` 一行：在 `&dc2;` 后插入 `&resub; &fraig; &sweep;` 三段保守 AIG 精简（b4）。`default.area`、`default.fast` 未改。diff：`abc9.cc.patch.diff`。 |
| `intel_CMakeLists.txt` | `techlibs/intel/CMakeLists.txt` | DATA_FILES 清单新增 `cycloneiv/cells_arith.v`。 |
| —（由 `apply_patches.sh` 追加） | `passes/opt/CMakeLists.txt` | 末尾追加 `yosys_pass(pmux_opt pmux_opt.cc)` 登记。 |

### 6.1 三条优化措施与规则边界

1. **R1 · 同构布尔分支公共操作数提出（`pmux_opt.cc`）**
   当一个 `$pmux` / `$mux` 的各分支由同型 `$xor` / `$and` / `$or`、等宽、无符号单元驱动，并共享公共操作数 C 时：
   `MUX(P_i op C) ≡ MUX(P_i) op C`，将 C 提出到 MUX 输出之后，消除 `分支数 − 1` 个重复布尔单元。
   - 安全约束：`$add` / `$sub` 不满足分配律，**禁止套用**；宽度不等、带符号、公共操作数回环到 MUX 输入位时安全放弃；仅处理 `$pmux` 与 `$mux`。

2. **路线 D · 宽位宽 ALU 行波进位（`cells_arith.v`）**
   宽位宽 `$alu` 用逐位 `$fa` 行波进位替代通用 techmap 的 Brent-Kung 前缀树；窄位宽回退通用实现以避免反增。CI / BI / X / CO 契约与通用 `$alu` 完全一致，**只改变进位网络结构，不改变逻辑**。

3. **b4 · 保守 abc9 内置脚本（`abc9.cc`）**
   在默认 AIG 精简链中统一插入 `&resub; &fraig; &sweep;`；脚本全 9 例统一，不按网表结构切换；未使用 `&syn2` 等激进综合命令（已实测会在反馈 / 时序用例上反增并回退）。

### 6.2 构建脚本口径

源码安装、两臂编译、面积对比、效率测量一律使用 `code/scripts/` 下的参数化 shell 脚本（见第 3、4 节）；早期空 pass 阶段的一次性 Python 调试脚本未随交付包提供，不构成构建依据。

---

## 7. EQY 形式等价验证（`code/eqy/`）

- **验证对象**：abc9 打包之后、专用单元映射之前的 `$lut` + 标准化内部 DFF 网表（答疑行 54-3）。
- **两臂**：gold = pristine 0.69 原版综合网表；gate = 优化版综合网表；均由自编译 0.69 流程导出。
- **结果**：**9 / 9 例 `DONE (PASS, rc=0)`，逐分区 SAT 证明 equivalent**；两臂 DFF 逐例完全一致。

| 目录 / 文件 | 内容 |
|---|---|
| `eqy/<case>/` | 每例 `.eqy`、`eqy.log`、两臂导出 `.ys` 与 RTLIL 网表；其中 `gold.ys` / `gate.ys` 是 `export_eqy_all.sh` 按本次运行目录生成的实例化快照（内含运行机绝对路径，仅作留档），换目录复跑会由脚本按新路径重新生成，模板以 `eqy/scripts/` 下两份为准。 |
| `eqy/scripts/eqy_gold.ys`、`eqy_gate.ys` | 两臂 RTLIL 导出模板（跳过 `ff_map.v` 保留标准内部 DFF；不执行 `autoname`） |
| `eqy/scripts/export_eqy_all.sh` | 批量两臂导出（gold=original 臂，gate=optimized 臂） |
| `eqy/scripts/run_eqy_all.sh` | 批量分区 SAT 证明 |
| `eqy/scripts/finalize_eqy_report.sh` | 汇总报告与归档校验生成 |
| `eqy/EQY等价验证报告.txt`、`EQY汇总表.txt`、`EQY两臂单元统计.txt`、`归档校验.txt` | 9 例证明结论、分区数 / 耗时、两臂单元对照与归档完整性校验 |

**复跑顺序（在 `code/` 目录下，WSL/Linux）：**

```bash
bash eqy/scripts/export_eqy_all.sh     # 1) 两臂导出 $lut 网表
bash eqy/scripts/run_eqy_all.sh       # 2) 逐分区 SAT 证明（需 eqy 在 PATH）
bash eqy/scripts/finalize_eqy_report.sh  # 3) 生成汇总报告与归档校验
```

环境变量（默认相对 `code/` 目录，均可覆盖）：`YOSYS_BASE` / `YOSYS_OPT` / `CASES_DIR` / `EQY_OUT`；`run_eqy_all.sh` 另支持 `EQY_BIN`（默认 PATH 中的 `eqy`）。

> EQY 的 SAT 证明步骤可使用配套 EQY 工具链（答疑行 53-Q4：EQY 可选其他版本、不计耗时）；**面积基准一律以自编译 0.69 两臂 `synth_intel` 结果为准**。
>
> 留档说明：包内 `eqy/<case>/` 的日志、网表与实例化 `.ys` 是在打包机上生成的快照，其中本机绝对路径已统一替换为 `<code>` / `<work>` / `<src-tree>` 等中性占位；复跑上述三步脚本会按当前目录重新生成这些文件，占位不影响证明结论与复跑。

---

## 8. 面积与效率实测口径

### 8.1 面积（`compare_result.txt`，自编译 0.69 两臂，`synth_intel -family cycloneiv`）

| 用例 | LUT 基线 | LUT 优化后 | 降幅 | FF 基线 | FF 优化后 |
|---|---:|---:|---:|---:|---:|
| test1 | 286 | 286 | 0.00% | 222 | 222 |
| test2 | 25 | 25 | 0.00% | 0 | 0 |
| test3 | 12 | 12 | 0.00% | 17 | 17 |
| test4 | 35 | 34 | 2.86% | 10 | 10 |
| pmux_case01_balanced | 426 | 392 | 7.98% | 12 | 12 |
| pmux_case02_pipeline | 450 | 450 | 0.00% | 24 | 24 |
| pmux_case03_crossbar | 408 | 373 | 8.58% | 10 | 10 |
| pmux_case04_feedback | 367 | 362 | 1.36% | 16 | 16 |
| pmux_case05_nested | 413 | 405 | 1.94% | 12 | 12 |
| **合计** | **2422** | **2339** | **总量 3.43%；逐例算术平均 2.52%** | **323** | **323** |

9 例 LUT 全部不反增、FF 全部不增加；各例 `check` 0 problems，abc9 `&verify` 全部等价。

### 8.2 效率口径

- **时间**：yosys 进程启动到综合结束的墙钟（含 abc 子进程等待；EQY 不计入）。
- **内存**：仅 yosys 主进程峰值 RSS（不含 abc 子进程）。
- **阈值**：比值 ≤1.05 满分；>1.05 警告；>1.15 该例该项不得分（时间 / 内存任一越线即判）。
- `scripts/measure_efficiency.sh` 在 WSL / Linux 下以 `/usr/bin/time -v` 采集；正式 Windows 环境按答疑行 132 预热、先原版后优化版测量。随包 `eqy/` 与效率历史参考结果见技术文档对应章节。

---

## 9. 红线与一致性约定（与答疑口径一致）

- 自定义 pass **编译进主程序**，未使用 plugin 动态加载；在 `synth_intel.cc` 内显式调用。
- 两臂综合脚本逐字相同，差别仅在二进制；Yosys 与 ABC 版本两臂统一。
- 使用 yosys **自带 abc9**，未更换内置另一个 abc 或外部 abc；abc 脚本全 9 例统一，不按网表结构切换。
- 综合命令统一 `synth_intel -family cycloneiv`；未做上板、eLinx 工程与仿真报告（赛题二不要求）。
