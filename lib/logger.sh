#!/bin/bash
# ============================================================================
# GLM_quota_kicker - 日志模块
# ============================================================================
# 功能：日志记录、终端输出、颜色控制
# ============================================================================

# 防止重复加载
[[ -n "${_LIB_LOGGER_LOADED:-}" ]] && return 0
_LIB_LOGGER_LOADED=true

# 加载配置模块
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# ============================================================================
# 日志配置
# ============================================================================
LOG_FILE="${QK_LOG_FILE:-$CONFIG_DIR/wake.log}"
LOG_LEVEL="${LOG_LEVEL:-info}"

# 终端颜色配置
# 检测是否在终端中运行，非终端环境使用空字符串
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    GRAY=$'\033[0;90m'
    NC=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' GRAY='' NC=''
fi

# ============================================================================
# 核心日志函数
# ============================================================================

# 写入日志到文件
# 参数:
#   $1 - 日志级别 (DEBUG/INFO/WARN/ERROR)
#   $@ - 日志消息
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 调试日志
# 仅在 LOG_LEVEL=debug 时输出
log_debug() {
    if [[ "$LOG_LEVEL" == "debug" ]]; then
        log "DEBUG" "$@"
    fi
    return 0
}

# 信息日志
log_info() {
    log "INFO" "$@"
}

# 警告日志
log_warn() {
    log "WARN" "$@"
}

# 错误日志
log_error() {
    log "ERROR" "$@"
}

# ============================================================================
# 用户输出函数
# ============================================================================

# 成功消息
# 参数: 消息内容
log_success() {
    local message="$1"
    echo -e "${GREEN}✓ $message${NC}"
    log_info "$message"
}

# 错误消息并退出
# 参数: 消息内容
log_error_exit() {
    local message="$1"
    echo -e "${RED}错误: $message${NC}" >&2
    log_error "$message"
    exit 1
}

# 信息消息
# 参数: 消息内容
log_info_msg() {
    local message="$1"
    echo -e "${CYAN}$message${NC}"
    log_info "$message"
}

# 警告消息
# 参数: 消息内容
log_warn_msg() {
    local message="$1"
    echo -e "${YELLOW}⚠ $message${NC}"
    log_warn "$message"
}

# ============================================================================
# 日志文件管理
# ============================================================================

# 获取日志文件路径
log_path() {
    echo "$LOG_FILE"
}

# 清空日志文件
log_clear() {
    > "$LOG_FILE"
    log_info "日志已清空"
}

# 查看日志（最后 N 行）
# 参数: 行数（默认 20）
log_tail() {
    local lines="${1:-20}"
    tail -n "$lines" "$LOG_FILE"
}

# 实时查看日志
log_follow() {
    tail -f "$LOG_FILE"
}

# 设置日志级别
# 参数: debug|info|warn|error
log_set_level() {
    local level="$1"
    case "$level" in
        debug|info|warn|error)
            LOG_LEVEL="$level"
            export LOG_LEVEL
            log_info "日志级别已设置为: $level"
            ;;
        *)
            log_error "无效的日志级别: $level"
            return 1
            ;;
    esac
}
