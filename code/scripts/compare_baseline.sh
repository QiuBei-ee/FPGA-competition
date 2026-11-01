#!/bin/bash
# =============================================================================
# 赛题二 PMUX 优化 · 两臂批量综合对比脚本（交付版，参数化 / 相对路径）
#
# 用法（在 WSL / Linux 环境运行，方案 B：交付 Linux 两臂产物 + 源码 + 构建脚本）：
#   bash compare_baseline.sh
#   YOSYS_BASE=/path/to/pristine/yosys  YOSYS_OPT=/path/to/optimized/yosys \
#       bash compare_baseline.sh --cases ../cases --out compare_result.txt
#
# 两臂综合命令逐字相同，差别只在 yosys 二进制本身（答疑行 37-1 / 53-Q2）：
#   read_verilog <case>; hierarchy -check -top <top>; synth_intel -family cycloneiv; stat
#
# 统计口径：LUT = cycloneiv_lcell_comb（含取反单元）；FF = dffeas。
# 判定：每个用例 LUT 不得反增、FF 不得多于基线；降幅按每例分别计算后取算术平均。
# =============================================================================
set -u

# ---- 相对路径定位（不写死本机绝对路径）--------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="$SCRIPT_DIR/../cases"
YOSYS_BASE="${YOSYS_BASE:-$SCRIPT_DIR/../bin/original/yosys}"
YOSYS_OPT="${YOSYS_OPT:-$SCRIPT_DIR/../bin/optimized/yosys}"
OUT_FILE="$SCRIPT_DIR/../compare_result.txt"

# ---- 9 个用例（顶层模块名 = 文件名主体）-------------------------------------
NAMES="test1 test2 test3 test4 pmux_case01_balanced pmux_case02_pipeline \
pmux_case03_crossbar pmux_case04_feedback pmux_case05_nested"

# 0.69 pristine 基线（同环境同参数编译的未改动原版实测，synth_intel cycloneiv）
declare -A BASE_LUT=( [test1]=286 [test2]=25 [test3]=12 [test4]=35 \
  [pmux_case01_balanced]=426 [pmux_case02_pipeline]=450 [pmux_case03_crossbar]=408 \
  [pmux_case04_feedback]=367 [pmux_case05_nested]=413 )
declare -A BASE_FF=( [test1]=222 [test2]=0 [test3]=17 [test4]=10 \
  [pmux_case01_balanced]=12 [pmux_case02_pipeline]=24 [pmux_case03_crossbar]=10 \
  [pmux_case04_feedback]=16 [pmux_case05_nested]=12 )

# ---- 命令行参数覆盖 ----------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --base)   YOSYS_BASE="$2"; shift 2 ;;
    --opt)    YOSYS_OPT="$2";  shift 2 ;;
    --cases) CASES_DIR="$2";   shift 2 ;;
    --out)    OUT_FILE="$2";   shift 2 ;;
    *) echo "unknown option: $1"; exit 2 ;;
  esac
done

# ---- 前置校验 ----------------------------------------------------------------
for bin in "$YOSYS_BASE" "$YOSYS_OPT"; do
  if [ ! -x "$bin" ]; then
    echo "[ERROR] yosys binary not executable: $bin"
    echo "        set YOSYS_BASE / YOSYS_OPT or place it under code/bin/{original,optimized}/"
    exit 1
  fi
done
if [ ! -d "$CASES_DIR" ]; then
  echo "[ERROR] cases directory not found: $CASES_DIR"; exit 1
fi

run_synth() {  # $1=yosys  $2=case stem  $3=log
  local yosys="$1" stem="$2" log="$3"
  "$yosys" -p "read_verilog $CASES_DIR/${stem}.v; hierarchy -check -top $stem; \
synth_intel -family cycloneiv; stat" > "$log" 2>&1
}

# 结果文件头部仅记录相对 code/ 的展示路径，不写入本机绝对路径
relpath() { local p="$1"; case "$p" in "$SCRIPT_DIR/"*) echo "${p#$SCRIPT_DIR/}";; *) echo "$p";; esac; }

count_cell() {  # $1=log  $2=celltype  -> 第一个计数（跳过 Generating 行）
  grep "$2" "$1" | grep -v Generating | awk '{print $1}' | head -1
}

: > "$OUT_FILE"
{
  echo "PMUX optimization two-arm comparison (Yosys 0.69, synth_intel -family cycloneiv)"
  echo "base: $(relpath "$YOSYS_BASE")"
  echo "opt : $(relpath "$YOSYS_OPT")"
  echo "cases: $(relpath "$CASES_DIR")"
  echo
  printf "%-26s %7s %7s %7s %8s %6s %6s\n" case LUT_base LUT_opt dLUT cut% FF_base FF_opt
} >> "$OUT_FILE"

tot_base=0; tot_opt=0; sum_cut=0.0; n=0; bad_lut=0; bad_ff=0; err=0

for stem in $NAMES; do
  blog="$SCRIPT_DIR/../logs/${stem}_base.log"
  olog="$SCRIPT_DIR/../logs/${stem}_opt.log"
  mkdir -p "$(dirname "$blog")"

  # 答疑行 132：先跑原版，再跑优化版
  run_synth "$YOSYS_BASE" "$stem" "$blog"
  run_synth "$YOSYS_OPT"  "$stem" "$olog"

  b_lut=$(count_cell "$blog" cycloneiv_lcell_comb); o_lut=$(count_cell "$olog" cycloneiv_lcell_comb)
  b_ff=$(count_cell "$blog" dffeas);          o_ff=$(count_cell "$olog" dffeas)
  [ -z "$b_ff" ] && b_ff=0; [ -z "$o_ff" ] && o_ff=0

  if [ -z "$b_lut" ] || [ -z "$o_lut" ]; then
    printf "%-26s  parse ERROR (check logs)\n" "$stem" >> "$OUT_FILE"; err=1; continue
  fi

  dlut=$(( b_lut - o_lut ))
  cut=$(awk -v b="$b_lut" -v o="$o_lut" 'BEGIN{printf "%.2f", (b-o)*100.0/b}')
  tot_base=$((tot_base + b_lut)); tot_opt=$((tot_opt + o_lut))
  sum_cut=$(awk -v s="$sum_cut" -v b="$b_lut" -v o="$o_lut" 'BEGIN{printf "%.4f", s+(b-o)*100.0/b}')
  n=$((n+1))

  # 红线校验：LUT 不得反增；FF 不得多于基线
  if [ "$o_lut" -gt "$b_lut" ]; then bad_lut=1; fi
  if [ "$o_ff" -gt "${BASE_FF[$stem]}" ]; then bad_ff=1; fi

  printf "%-26s %7s %7s %7s %8s %6s %6s\n" "$stem" "$b_lut" "$o_lut" "$dlut" "$cut" "$b_ff" "$o_ff" >> "$OUT_FILE"

  # 错误扫描（原版基线日志中固有的非致命 ABC 回退提示已在报告 4.1 说明，不视为错误）
  grep -iE '^ERROR|critical|traceback|segmentation' "$olog" | head -3 | sed 's/^/  [!] /' >> "$OUT_FILE"
done

avg_cut=$(awk -v s="$sum_cut" -v n="$n" 'BEGIN{printf "%.2f", s/n}')
tot_cut=$(awk -v b="$tot_base" -v o="$tot_opt" 'BEGIN{printf "%.2f", (b-o)*100.0/b}')

{
  echo
  printf "TOTAL LUT: base=%d opt=%d  total reduction=%s%%\n" "$tot_base" "$tot_opt" "$tot_cut"
  printf "PER-CASE ARITHMETIC AVERAGE reduction: %s%%  (n=%d)\n" "$avg_cut" "$n"
  echo
  if [ "$bad_lut" -eq 1 ]; then echo "[FAIL] 存在用例 LUT 反增，违反红线（答疑行 115-2 / 130-2）。"; else echo "[OK] 所有用例 LUT 均未反增。"; fi
  if [ "$bad_ff" -eq 1 ]; then echo "[FAIL] 存在用例 FF 多于基线。"; else echo "[OK] 所有用例 FF 未增加。"; fi
  if [ "$err" -eq 1 ]; then echo "[FAIL] 存在日志解析错误，请检查 logs/。"; fi
} >> "$OUT_FILE"

cat "$OUT_FILE"
