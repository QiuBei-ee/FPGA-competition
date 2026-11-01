#!/bin/bash
# =============================================================================
# EQY 两臂 RTLIL 导出（交付版，参数化 / 相对路径）
#
# gold 臂 = code/bin/original/yosys（pristine 0.69，无自定义 pass、无路线 D）
# gate 臂 = code/bin/optimized/yosys（R1 pmux_opt + 路线 D + b4 内置 abc9 脚本）
# 两臂均在 abc9 打包之后、专用单元映射之前停止，导出 $lut + 标准内部 DFF 网表。
#
# 环境变量（均可覆盖；默认相对本脚本定位到 code/ 目录）：
#   YOSYS_BASE   pristine 0.69 可执行程序
#   YOSYS_OPT    optimized 0.69 可执行程序
#   CASES_DIR    9 个用例 Verilog 目录
#   EQY_OUT      EQY 工作/归档根目录（每例子目录 <stem>/）
#
# 输出：EQY_OUT/EQY两臂单元统计.txt（两臂 $lut / DFF 计数对照）
# =============================================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

YOSYS_BASE="${YOSYS_BASE:-$CODE_DIR/bin/original/yosys}"
YOSYS_OPT="${YOSYS_OPT:-$CODE_DIR/bin/optimized/yosys}"
CASES_DIR="${CASES_DIR:-$CODE_DIR/cases}"
EQY_OUT="${EQY_OUT:-$CODE_DIR/eqy}"

STEMS="test1 test2 test3 test4 pmux_case01_balanced pmux_case02_pipeline \
pmux_case03_crossbar pmux_case04_feedback pmux_case05_nested"

for bin in "$YOSYS_BASE" "$YOSYS_OPT"; do
  [ -x "$bin" ] || { echo "[ERROR] yosys not executable: $bin"; exit 1; }
done
[ -d "$CASES_DIR" ] || { echo "[ERROR] cases not found: $CASES_DIR"; exit 1; }
mkdir -p "$EQY_OUT"

STAT="$EQY_OUT/EQY两臂单元统计.txt"
: > "$STAT"
echo -e "case\tgold_lut\tgold_dff\tgate_lut\tgate_dff\texport" >> "$STAT"

for stem in $STEMS; do
  d="$EQY_OUT/$stem"
  mkdir -p "$d"
  sed -e "s#CASEFILE#$CASES_DIR/$stem.v#" -e "s#TOPNAME#$stem#" -e "s#OUTPATH#$d/gold.ilang#" \
      "$SCRIPT_DIR/eqy_gold.ys" > "$d/gold.ys"
  sed -e "s#CASEFILE#$CASES_DIR/$stem.v#" -e "s#TOPNAME#$stem#" -e "s#OUTPATH#$d/gate.ilang#" \
      "$SCRIPT_DIR/eqy_gate.ys" > "$d/gate.ys"

  g_ok=ok; e_ok=ok
  "$YOSYS_BASE" -s "$d/gold.ys" > "$d/gold.log" 2>&1 || g_ok=FAIL
  "$YOSYS_OPT"  -s "$d/gate.ys"  > "$d/gate.log" 2>&1 || e_ok=FAIL

  gl=$(grep -c '^  cell \$lut' "$d/gold.ilang" 2>/dev/null)
  gd=$(grep -E '^  cell \$_DFF' "$d/gold.ilang" 2>/dev/null | wc -l)
  el=$(grep -c '^  cell \$lut' "$d/gate.ilang" 2>/dev/null)
  ed=$(grep -E '^  cell \$_DFF' "$d/gate.ilang" 2>/dev/null | wc -l)
  gl=${gl:-0}; gd=${gd:-0}; el=${el:-0}; ed=${ed:-0}

  [ "$g_ok" = ok ] && [ "$e_ok" = ok ] && export=ok || export=FAIL
  echo -e "$stem\t$gl\t$gd\t$el\t$ed\t$export" >> "$STAT"
done

cat "$STAT"
