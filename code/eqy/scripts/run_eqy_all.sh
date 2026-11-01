#!/bin/bash
# =============================================================================
# EQY 逐分区 SAT 等价证明（交付版，参数化 / 相对路径）
#
# 前置：先运行 export_eqy_all.sh 生成两臂 gold.ilang / gate.ilang。
# EQY 工具链可使用其他版本（答疑行 53-Q4：EQY 可选其他版本、不计耗时，仅用于证明等价）。
#
# 环境变量：
#   EQY_BIN    eqy 可执行程序（默认 PATH 中的 `eqy`）
#   EQY_OUT    EQY 工作/归档根目录（默认 code/eqy）
#
# 输出：EQY_OUT/EQY汇总表.txt（case/result/rc/elapsed_sec/conclusion）
# =============================================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

EQY_BIN="${EQY_BIN:-eqy}"
EQY_OUT="${EQY_OUT:-$CODE_DIR/eqy}"

STEMS="test1 test2 test3 test4 pmux_case01_balanced pmux_case02_pipeline \
pmux_case03_crossbar pmux_case04_feedback pmux_case05_nested"

command -v "$EQY_BIN" >/dev/null 2>&1 || { echo "[ERROR] eqy not found: $EQY_BIN"; exit 1; }

RPT="$EQY_OUT/EQY汇总表.txt"
: > "$RPT"
echo -e "case\tresult\texit\telapsed_sec\tconclusion" >> "$RPT"

for stem in $STEMS; do
  d="$EQY_OUT/$stem"
  [ -f "$d/gold.ilang" ] || { echo "[ERROR] missing $d/gold.ilang; run export_eqy_all.sh first"; exit 1; }
  [ -f "$d/gate.ilang" ]  || { echo "[ERROR] missing $d/gate.ilang; run export_eqy_all.sh first"; exit 1; }

  cat > "$d/$stem.eqy" <<EOF
[options]

[gold]
read_rtlil $d/gold.ilang
prep -top $stem

[gate]
read_rtlil $d/gate.ilang
prep -top $stem

[strategy sat]
use sat
depth 20
EOF

  rm -rf "$d/work"
  start=$(date +%s)
  ( cd "$d" && "$EQY_BIN" --force -d "$d/work" "$stem.eqy" > "$d/eqy.log" 2>&1 )
  rc=$?
  end=$(date +%s)
  el=$((end-start))

  if grep -q "Successfully proved designs equivalent" "$d/eqy.log"; then
    result=PASS; conclusion="equivalent"
  elif grep -q "DONE (FAIL" "$d/eqy.log" || grep -qi "not equivalent\|counter-example" "$d/eqy.log"; then
    result=FAIL; conclusion="mismatch"
  else
    result=UNKNOWN; conclusion="check log"
  fi
  echo -e "$stem\t$result\t$rc\t$el\t$conclusion" >> "$RPT"
done

cat "$RPT"
