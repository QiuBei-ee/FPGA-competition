#!/bin/bash
# =============================================================================
# EQY 汇总报告生成（交付版，参数化 / 相对路径）
#
# 读取 export_eqy_all.sh / run_eqy_all.sh 产物，生成：
#   EQY_OUT/EQY等价验证报告.txt   正式证明报告（结果、rc、耗时、分区数、逐分区 SAT 摘录）
#   EQY_OUT/归档校验.txt          9 例 PASS/DONE 与六文件完整性校验
#
# 环境变量：EQY_OUT（默认 code/eqy）
# =============================================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
EQY_OUT="${EQY_OUT:-$CODE_DIR/eqy}"

STEMS="test1 test2 test3 test4 pmux_case01_balanced pmux_case02_pipeline \
pmux_case03_crossbar pmux_case04_feedback pmux_case05_nested"

REPORT="$EQY_OUT/EQY等价验证报告.txt"
CHECK="$EQY_OUT/归档校验.txt"

# 从汇总表读取 elapsed_sec（run_eqy_all.sh 的 wall-clock）
declare -A ELAPSED RESULT RC
while IFS=$'\t' read -r stem result rc elapsed conclusion; do
  [ "$stem" = "case" ] && continue
  [ -z "$stem" ] && continue
  RESULT[$stem]="$result"; RC[$stem]="$rc"; ELAPSED[$stem]="$elapsed"
done < "$EQY_OUT/EQY汇总表.txt"

: > "$REPORT"
echo "EQY FORMAL EQUIVALENCE CHECK REPORT (gold=pristine 0.69, gate=optimized 0.69)" >> "$REPORT"
echo "======================================================================" >> "$REPORT"
printf "%-26s %-6s %-4s %-8s %s\n" case result rc elapsed_sec partitions >> "$REPORT"

allpass=1
: > "$CHECK"
for stem in $STEMS; do
  f="$EQY_OUT/$stem/eqy.log"
  [ -f "$f" ] || { echo "[ERROR] missing $f"; exit 1; }
  rc=$(grep -oE 'rc=[0-9]+' "$f" | head -1 | tr -d 'rc=')
  np=$(grep -c "Proved equivalence of partition" "$f")
  el=${ELAPSED[$stem]:-0}
  if grep -q "Successfully proved designs equivalent" "$f"; then res=PASS; else res=FAIL; allpass=0; fi
  printf "%-26s %-6s %-4s %-8s %s\n" "$stem" "$res" "$rc" "$el" "$np" >> "$REPORT"

  pass=$(grep -c "Successfully proved designs equivalent" "$f")
  done_=$(grep -c "DONE (PASS" "$f")
  files="eqy.log gate.ilang gate.ys gold.ilang gold.ys $stem.eqy"
  missing=""
  for x in $files; do [ -f "$EQY_OUT/$stem/$x" ] || missing="$missing $x"; done
  [ -n "$missing" ] && flag="MISSING:$missing" || flag="files=[$files]"
  echo "$stem  PASS=$pass  DONE=$done_  $flag" >> "$CHECK"
done

echo "----------------------------------------------------------------------" >> "$REPORT"
if [ "$allpass" = 1 ]; then echo "ALL 9 DESIGNS PROVED EQUIVALENT" >> "$REPORT"; else echo "SOME DESIGNS NOT PROVED" >> "$REPORT"; fi
echo "" >> "$REPORT"
echo "Per-case partition proofs:" >> "$REPORT"
for stem in $STEMS; do
  echo "== $stem ==" >> "$REPORT"
  # 摘录证明行；将 eqy 打印的运行机工作目录方括号前缀中性化为 [work]，不写入本机绝对路径
  grep -E "Proved equivalence of partition|Successfully proved designs equivalent|DONE \(" \
    "$EQY_OUT/$stem/eqy.log" \
    | sed -E 's#\[[^]]*/work\]#[work]#' >> "$REPORT"
done

if [ "$allpass" = 1 ]; then echo "ALL_OK=1" >> "$CHECK"; else echo "ALL_OK=0" >> "$CHECK"; fi

cat "$REPORT"
echo
cat "$CHECK"
