#!/bin/bash
# =============================================================================
# 从 Yosys 0.69 源码树构建 yosys（交付版，参数化）
#
# 前置依赖（Ubuntu/WSL）：g++、cmake、make、python3、bison、flex、libffi-dev 等
#   （本构建关闭 readline/editline/zlib/libffi/python/slang/单元测试，仅需基础编译链）。
#
# 用法：
#   # 1) 原版（干净 0.69，不打补丁）
#   bash build_yosys.sh --src /path/to/yosys-0.69 --build /path/to/build-base --mode pristine
#
#   # 2) 优化版（先安装 code/src 改动，再构建）
#   bash build_yosys.sh --src /path/to/yosys-0.69 --build /path/to/build-opt --mode optimized
#
# 产物：build 目录下 yosys、yosys-abc；share 数据随安装/运行目录相对定位。
# 注意：pristine 与 optimized 应使用两份独立源码树，或先备份 pristine 产物再打补丁。
# =============================================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YSRC=""; BUILD=""; MODE="optimized"; JOBS="$(nproc 2>/dev/null || echo 4)"

while [ $# -gt 0 ]; do
  case "$1" in
    --src)   YSRC="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --mode)  MODE="$2"; shift 2 ;;
    --jobs)  JOBS="$2"; shift 2 ;;
    *) echo "unknown option: $1"; exit 2 ;;
  esac
done

[ -d "$YSRC" ]       || { echo "[ERROR] --src <source dir> missing"; exit 1; }
[ -n "$BUILD" ]      || { echo "[ERROR] --build <build dir> missing"; exit 1; }
case "$MODE" in pristine|optimized) ;; *) echo "[ERROR] --mode pristine|optimized"; exit 1 ;; esac

# optimized：先安装本次优化补丁（幂等）
if [ "$MODE" = "optimized" ]; then
  bash "$SCRIPT_DIR/apply_patches.sh" --src "$YSRC" || exit 1
fi

mkdir -p "$BUILD"
cd "$BUILD" || exit 1

# CMake 开关与交付实测构建一致（Release；关闭 TCL/readline/editline/zlib/libffi/python/slang/单测；内置 abc）
cmake "$YSRC" \
  -DCMAKE_BUILD_TYPE=Release \
  -DYOSYS_WITHOUT_TCL=ON \
  -DYOSYS_WITHOUT_READLINE=ON \
  -DYOSYS_WITHOUT_EDITLINE=ON \
  -DYOSYS_WITHOUT_ZLIB=ON \
  -DYOSYS_WITHOUT_LIBFFI=ON \
  -DYOSYS_WITHOUT_SLANG=ON \
  -DYOSYS_WITH_PYTHON=OFF \
  -DYOSYS_ENABLE_UNIT_TESTS=OFF \
  -DYOSYS_ENABLE_FUNCTIONAL_TESTS=OFF \
  -DYOSYS_WITHOUT_ABC=OFF \
  -DYOSYS_DISABLE_THREADS=OFF \
  || { echo "[ERROR] cmake configure failed"; exit 1; }

make -j"$JOBS" yosys yosys-abc || { echo "[ERROR] make failed"; exit 1; }

echo
echo "[OK] $MODE build finished: $BUILD/yosys"
"$BUILD/yosys" -V
