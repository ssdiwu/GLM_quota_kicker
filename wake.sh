#!/bin/bash
# ============================================================================
# GLM_quota_kicker - 入口脚本
# ============================================================================
# 功能：调用 bin/wake 执行实际功能
# 这是项目的主入口，保持向后兼容性
# ============================================================================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_EXECUTABLE="$SCRIPT_DIR/bin/wake"

# 检查 bin/wake 是否存在
if [[ ! -f "$MAIN_EXECUTABLE" ]]; then
    echo "错误: 找不到 $MAIN_EXECUTABLE" >&2
    echo "请确保项目结构完整" >&2
    echo "提示: 如果您刚克隆项目，请检查 bin/ 目录是否存在" >&2
    exit 1
fi

# 检查是否可执行
if [[ ! -x "$MAIN_EXECUTABLE" ]]; then
    echo "错误: $MAIN_EXECUTABLE 没有执行权限" >&2
    echo "请运行: chmod +x $MAIN_EXECUTABLE" >&2
    exit 1
fi

# 调用实际的执行文件，传递所有参数
exec "$MAIN_EXECUTABLE" "$@"
