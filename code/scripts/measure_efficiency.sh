#!/bin/bash
# =============================================================================
# 赛题二 · 两臂运行时间 / 峰值内存效率测量（交付版，参数化 / 相对路径）
#
# 口径（答疑行 54-1/2、87-2、101-2、132、133）：
#   - 时间：yosys 进程启动到综合结束的墙钟（含 abc 子进程等待；EQY 不计入）
#   - 内存：yosys 主进程峰值 RSS（不统计 abc 子进程）
#   - 每例先原版后优化版；<1s 小例复核 5 次取平均；一次运行同时拿到时间与内存
#   - 阈值：比值 <=1.05 满分；>1.05 警告；>1.15 该项不得分（两指标任一越线即判）
#
# 用法：
#   YOSYS_BASE=../bin/original/yosys YOSYS_OPT=../bin/optimized/yosys \
#       bash measure_efficiency.sh [runs]
#   $1 = 重复次数（默认 5，答疑行 132 小例 5 次平均）
# =============================================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="${CASES_DIR:-$SCRIPT_DIR/../cases}"
YOSYS_BASE="${YOSYS_BASE:-$SCRIPT_DIR/../bin/original/yosys}"
YOSYS_OPT="${YOSYS_OPT:-$SCRIPT_DIR/../bin/optimized/yosys}"
OUT_FILE="${OUT_FILE:-$SCRIPT_DIR/../efficiency_result.txt}"
RUNS="${1:-5}"

NAMES="test1 test2 test3 test4 pmux_case01_balanced pmux_case02_pipeline \
pmux_case03_crossbar pmux_case04_feedback pmux_case05_nested"

for bin in "$YOSYS_BASE" "$YOSYS_OPT"; do
  [ -x "$bin" ] || { echo "[ERROR] not executable: $bin"; exit 1; }
done
command -v /usr/bin/time >/dev/null 2>&1 || { echo "[ERROR] /usr/bin/time (GNU time) required"; exit 1; }

parse_elapsed() {
  local line hms m s
  line=$(grep 'Elapsed (wall clock) time' "$1"); hms=${line##*: }
  if [[ "$hms" == *:*:* ]]; then
    local h; h=$(echo "$hms"|cut -d: -f1); m=$(echo "$hms"|cut -d: -f2); s=$(echo "$hms"|cut -d: -f3)
    awk -v h="$h" -v m="$m" -v s="$s" 'BEGIN{printf "%.3f", h*3600+m*60+s}'
  else
    m=$(echo "$hms"|cut -d: -f1); s=$(echo "$hms"|cut -d: -f2)
    awk -v m="$m" -v s="$s" 'BEGIN{printf "%.3f", m*60+s}'
  fi
}
parse_rss() { grep 'Maximum resident set size' "$1" | awk '{print $6/1024}'; }

relpath() { local p="$1"; case "$p" in "$SCRIPT_DIR/"*) echo "${p#$SCRIPT_DIR/}";; *) echo "$p";; esac; }

run_once() {  # $1=bin $2=stem $3=tag $4=idx  -> stdout "sec rssMB"
  local bin="$1" stem="$2" tag="$3" idx="$4"
  local log="$SCRIPT_DIR/../logs/eff_${stem}_${tag}_${idx}.log"
  mkdir -p "$(dirname "$log")"
  /usr/bin/time -v "$bin" -p "read_verilog $CASES_DIR/${stem}.v; hierarchy -check -top $stem; \
synth_intel -family cycloneiv; stat" > "$log" 2> "${log}.time"
  echo "$(parse_elapsed "${log}.time") $(parse_rss "${log}.time")"
}

: > "$OUT_FILE"
{
  echo "Efficiency comparison (${RUNS}-run average, wall-clock s / main-process peak RSS MB)"
  echo "base: $(relpath "$YOSYS_BASE")"
  echo "opt : $(relpath "$YOSYS_OPT")"
  echo
  printf "%-26s %9s %9s %7s %9s %9s %7s  %s\n" case t_base t_opt t_ratio mem_b mem_o mem_ratio verdict
} >> "$OUT_FILE"

tb=0; to=0; mb=0; mo=0
for stem in $NAMES; do
  # 预热（不计入平均），先原版后优化版
  "$YOSYS_BASE" -p "read_verilog $CASES_DIR/${stem}.v; hierarchy -check -top $stem; synth_intel -family cycloneiv" >/dev/null 2>&1
  "$YOSYS_OPT"  -p "read_verilog $CASES_DIR/${stem}.v; hierarchy -check -top $stem; synth_intel -family cycloneiv" >/dev/null 2>&1

  bt=0; br=0; ot=0; or_=0; i=1
  while [ "$i" -le "$RUNS" ]; do
    read b_t b_r < <(run_once "$YOSYS_BASE" "$stem" base "$i")
    read o_t o_r < <(run_once "$YOSYS_OPT"  "$stem" opt  "$i")
    bt=$(awk -v x="$bt" -v y="$b_t" 'BEGIN{print x+y}')
    br=$(awk -v x="$br" -v y="$b_r" 'BEGIN{print x+y}')
    ot=$(awk -v x="$ot" -v y="$o_t" 'BEGIN{print x+y}')
    or_=$(awk -v x="$or_" -v y="$o_r" 'BEGIN{print x+y}')
    i=$((i+1))
  done
  tbv=$(awk -v x="$bt" -v n="$RUNS" 'BEGIN{printf "%.3f", x/n}')
  mbv=$(awk -v x="$br" -v n="$RUNS" 'BEGIN{printf "%.3f", x/n}')
  tov=$(awk -v x="$ot" -v n="$RUNS" 'BEGIN{printf "%.3f", x/n}')
  mov=$(awk -v x="$or_" -v n="$RUNS" 'BEGIN{printf "%.3f", x/n}')

  tr=$(awk -v a="$tov" -v b="$tbv" 'BEGIN{printf "%.3f", a/b}')
  mr=$(awk -v a="$mov" -v b="$mbv" 'BEGIN{printf "%.3f", a/b}')

  if awk -v tr="$tr" -v mr="$mr" 'BEGIN{exit !(tr>1.15 || mr>1.15)}'; then verdict="FAIL(>1.15)"
  elif awk -v tr="$tr" -v mr="$mr" 'BEGIN{exit !(tr>1.05 || mr>1.05)}'; then verdict="WARN(>5%)"
  else verdict="OK"; fi

  printf "%-26s %9s %9s %7s %9s %9s %7s  %s\n" "$stem" "$tbv" "$tov" "$tr" "$mbv" "$mov" "$mr" "$verdict" >> "$OUT_FILE"
  tb=$(awk -v x="$tb" -v y="$tbv" 'BEGIN{print x+y}')
  to=$(awk -v x="$to" -v y="$tov" 'BEGIN{print x+y}')
  mb=$(awk -v x="$mb" -v y="$mbv" 'BEGIN{print x+y}')
  mo=$(awk -v x="$mo" -v y="$mov" 'BEGIN{print x+y}')
done

tr_all=$(awk -v a="$to" -v b="$tb" 'BEGIN{printf "%.3f", a/b}')
mr_all=$(awk -v a="$mo" -v b="$mb" 'BEGIN{printf "%.3f", a/b}')
{
  echo
  printf "%-26s %9s %9s %7s %9s %9s %7s\n" TOTAL "$tb" "$to" "$tr_all" "$mb" "$mo" "$mr_all"
  echo
  echo "Threshold: <=1.05 full mark; >1.05 warn; >1.15 no score for that case (either metric)."
} >> "$OUT_FILE"
cat "$OUT_FILE"
