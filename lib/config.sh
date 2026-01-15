#!/bin/bash
# ============================================================================
# GLM_quota_kicker - 配置管理模块
# ============================================================================
# 功能：配置文件的加载、解析、验证和管理
# ============================================================================

# 防止重复加载
[[ -n "${_LIB_CONFIG_LOADED:-}" ]] && return 0
_LIB_CONFIG_LOADED=true

# ============================================================================
# 配置路径
# ============================================================================
CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$CONFIG_DIR/config.jsonc"
SCHEDULE_FILE="$CONFIG_DIR/.schedule.json"

# ============================================================================
# 从 JSONC 文件读取配置值
# ============================================================================
# 参数:
#   $1 - jq 查询路径 (如: '.api.key')
# 返回:
#   配置值或错误信息
# ----------------------------------------------------------------------------
config_get() {
    local jq_query="$1"

    # 检查文件是否存在
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "错误: 配置文件不存在: $CONFIG_FILE" >&2
        return 1
    fi

    # 检查 jq 是否安装
    if ! command -v jq &> /dev/null; then
        echo "错误: 需要安装 jq 工具" >&2
        echo "请运行: brew install jq (macOS) 或 apt install jq (Linux)" >&2
        return 1
    fi

    # 去除注释（支持 // 和 /* */ 风格）
    local json_content
    json_content=$(sed '/^[[:space:]]*\/\/.*$/d' "$CONFIG_FILE" | \
                  sed 's|/\*.*\*/||g' | \
                  sed 's|//[^\"]*$||g' | \
                  sed 's|,[[:space:]]*\}|}|g' | \
                  sed 's|,[[:space:]]*\]|]|g')

    # 使用 jq 解析
    echo "$json_content" | jq -r "$jq_query" 2>/dev/null
}

# ============================================================================
# 加载配置到全局变量
# ============================================================================
# 加载的变量:
#   API_KEY, MODEL, PROVIDER_NAME, BASE_URL, ENDPOINT, AUTH_HEADER
#   PROMPTS_ARRAY, HAS_CUSTOM_PROMPTS
# 返回:
#   0 成功, 1 失败
# ----------------------------------------------------------------------------
config_load() {
    # 加载 API 配置
    export API_KEY="$(config_get '.api.key')"
    export MODEL="$(config_get '.api.model')"

    # 加载服务商配置
    export PROVIDER_NAME="$(config_get '.provider.name')"
    export BASE_URL="$(config_get '.provider.baseUrl')"
    export ENDPOINT="$(config_get '.provider.endpoint')"
    export AUTH_HEADER="$(config_get '.provider.authHeader')"

    # 加载 prompts 配置（可选）
    local prompts_json
    prompts_json=$(config_get '.request.prompts')

    if [[ -n "$prompts_json" && "$prompts_json" != "null" ]]; then
        # 将 JSON 数组转换为 bash 数组
        local prompts_raw
        prompts_raw=$(echo "$prompts_json" | jq -r '.[]' 2>/dev/null)

        if [[ -n "$prompts_raw" ]]; then
            # 先取消可能存在的旧数组
            unset PROMPTS_ARRAY
            # 声明数组（不使用export，避免函数作用域问题）
            PROMPTS_ARRAY=()
            while IFS= read -r line || [[ -n "$line" ]]; do
                # 跳过空行
                [[ -z "$line" ]] && continue
                PROMPTS_ARRAY+=("$line")
            done < <(printf '%s' "$prompts_raw")
            # 数组填充后再export
            export PROMPTS_ARRAY

            # 设置标志表示使用了自定义 prompts
            export HAS_CUSTOM_PROMPTS=true
        fi
    fi

    return 0
}

# ============================================================================
# 验证配置完整性
# ============================================================================
# 检查的配置项:
#   API_KEY, MODEL, BASE_URL, ENDPOINT, AUTH_HEADER
# 返回:
#   0 配置完整, 1 配置不完整
# ----------------------------------------------------------------------------
config_validate() {
    local errors=0

    [[ -z "${API_KEY:-}" ]] && { echo "错误: API_KEY 未配置" >&2; ((errors++)); }
    [[ -z "${MODEL:-}" ]] && { echo "错误: MODEL 未配置" >&2; ((errors++)); }
    [[ -z "${BASE_URL:-}" ]] && { echo "错误: BASE_URL 未配置" >&2; ((errors++)); }
    [[ -z "${ENDPOINT:-}" ]] && { echo "错误: ENDPOINT 未配置" >&2; ((errors++)); }
    [[ -z "${AUTH_HEADER:-}" ]] && { echo "错误: AUTH_HEADER 未配置" >&2; ((errors++)); }

    return $errors
}

# ============================================================================
# 检查配置文件是否存在
# ============================================================================
# 返回:
#   0 存在, 1 不存在
# ----------------------------------------------------------------------------
config_exists() {
    [[ -f "$CONFIG_FILE" ]]
}

# ============================================================================
# 获取配置文件路径
# ============================================================================
# 返回:
#   配置文件的绝对路径
# ----------------------------------------------------------------------------
config_path() {
    echo "$CONFIG_FILE"
}

# ============================================================================
# 获取调度文件路径
# ============================================================================
# 返回:
#   调度文件的绝对路径
# ----------------------------------------------------------------------------
config_schedule_path() {
    echo "$SCHEDULE_FILE"
}
