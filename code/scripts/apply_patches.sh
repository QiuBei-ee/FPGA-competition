#!/bin/bash
# =============================================================================
# 把本次优化改动安装到一份干净的 Yosys 0.69 源码树（交付版，参数化 / 幂等）
#
# 前置：源码树已 checkout 到 v0.69（commit 9f75ca1f9），abc 等 submodule 齐全。
# 用法：
#   bash apply_patches.sh --src /absolute/path/to/yosys-0.69
#
# 改动清单（与 code/src 一一对应；相对源码树路径）：
#   code/src/pmux_opt.cc            -> passes/opt/pmux_opt.cc                 (新增)
#   code/src/abc9.cc                -> passes/techmap/abc9.cc                 (整文件，仅 default 脚本一行改动)
#   code/src/cells_arith.v          -> techlibs/intel/cycloneiv/cells_arith.v (整文件，路线 D ripple-carry $alu)
#   code/src/synth_intel.cc.optimized -> techlibs/intel/synth_intel.cc        (整文件，仅 +2 行调用)
#   code/src/intel_CMakeLists.txt   -> techlibs/intel/CMakeLists.txt          (整文件，DATA_FILES 增加 cells_arith.v)
#   passes/opt/CMakeLists.txt       -> 追加 yosys_pass(pmux_opt pmux_opt.cc)  (幂等)
#
# 原版未改动文件保持 0.69 上游内容；diff 见 code/src/*.patch.diff。
# =============================================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"
YSRC=""

while [ $# -gt 0 ]; do
  case "$1" in
    --src) YSRC="$2"; shift 2 ;;
    *) echo "unknown option: $1"; exit 2 ;;
  esac
done

if [ -z "$YSRC" ] || [ ! -d "$YSRC" ]; then
  echo "[ERROR] specify an existing 0.69 source tree with --src <dir>"; exit 1
fi
if [ ! -f "$YSRC/kernel/yosys.h" ]; then
  echo "[ERROR] $YSRC does not look like a yosys source tree (missing kernel/yosys.h)"; exit 1
fi

copy() {  # $1=src(basename in code/src)  $2=dst(relative to source tree)
  local from="$SRC_DIR/$1" to="$YSRC/$2"
  if [ ! -f "$from" ]; then echo "[ERROR] missing $from"; exit 1; fi
  mkdir -p "$(dirname "$to")"
  cp -f "$from" "$to"
  echo "[install] $2"
}

copy pmux_opt.cc              passes/opt/pmux_opt.cc
copy abc9.cc                  passes/techmap/abc9.cc
copy cells_arith.v            techlibs/intel/cycloneiv/cells_arith.v
copy synth_intel.cc.optimized techlibs/intel/synth_intel.cc
copy intel_CMakeLists.txt      techlibs/intel/CMakeLists.txt

# 幂等追加 pmux_opt 到 passes/opt/CMakeLists.txt
opt_cm="$YSRC/passes/opt/CMakeLists.txt"
if ! grep -q 'pmux_opt' "$opt_cm"; then
  [ -z "$(tail -c 1 "$opt_cm")" ] || echo >> "$opt_cm"
  cat >> "$opt_cm" <<'EOF'
# --- competition custom pass (pmux_opt) ---
yosys_pass(pmux_opt
	pmux_opt.cc
)
EOF
  echo "[install] passes/opt/CMakeLists.txt registered pmux_opt"
else
  echo "[skip] passes/opt/CMakeLists.txt already registers pmux_opt"
fi

echo
echo "Patches applied. Next: bash build_yosys.sh --src $YSRC --mode optimized"
