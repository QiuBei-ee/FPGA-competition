#!/bin/bash
# =============================================================================
# 单例综合封装（交付版，参数化 / 相对路径）
#
# 用法：
#   YOSYS=/path/to/yosys bash run_one.sh pmux_case01_balanced
#   YOSYS=/path/to/yosys bash run_one.sh test1 ./out/test1.log
#
# $1 = 用例名（= Verilog 文件名主体 = 顶层模块名），必填
# $2 = 输出日志路径（可选，默认 ../logs/<name>.log）
# 综合命令固定：hierarchy -check -top <name>; synth_intel -family cycloneiv; stat
# =============================================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="${CASES_DIR:-$SCRIPT_DIR/../cases}"
YOSYS="${YOSYS:-$SCRIPT_DIR/../bin/optimized/yosys}"

stem="${1:-}"
if [ -z "$stem" ]; then
  echo "usage: YOSYS=/path/to/yosys bash run_one.sh <case_stem> [log_path]"; exit 1
fi
log="${2:-$SCRIPT_DIR/../logs/${stem}.log}"
mkdir -p "$(dirname "$log")"

casefile="$CASES_DIR/${stem}.v"
if [ ! -f "$casefile" ]; then echo "[ERROR] not found: $casefile"; exit 1; fi
if [ ! -x "$YOSYS" ]; then echo "[ERROR] yosys not executable: $YOSYS"; exit 1; fi

"$YOSYS" -p "read_verilog $casefile; hierarchy -check -top $stem; \
synth_intel -family cycloneiv; stat" > "$log" 2>&1

echo "=== $stem LUT / FF ==="
grep 'cycloneiv_lcell_comb' "$log" | grep -v Generating | awk '{print "LUT:", $1}' | head -1
grep 'dffeas' "$log" | grep -v Generating | awk '{print "FF :", $1}' | head -1
echo "log: $log"
