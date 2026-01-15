#!/bin/bash
# ============================================================================
# GLM_quota_kicker - API 请求模块
# ============================================================================
# 功能：API 请求发送、响应解析、错误处理
# ============================================================================

# 防止重复加载
[[ -n "${_LIB_API_LOADED:-}" ]] && return 0
_LIB_API_LOADED=true

# 加载依赖模块
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# ============================================================================
# API 配置
# ============================================================================
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-30}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-10}"
CONTENT_TYPE="${CONTENT_TYPE:-application/json}"

# 设置消息
api_set_prompt() {
    if [[ "${HAS_CUSTOM_PROMPTS:-false}" == true && ${#PROMPTS_ARRAY[@]} -gt 0 ]]; then
        export PROMPT=$(utils_random_choice PROMPTS_ARRAY)
        log_debug "使用自定义消息: $PROMPT"
    else
        export PROMPT="${PROMPT:-hi}"
        log_debug "使用默认消息"
    fi
}

# ============================================================================
# 构建请求体
# ============================================================================
# 返回: JSON 格式的请求体
# ----------------------------------------------------------------------------
api_build_body() {
    cat << EOF
{
    "model": "$MODEL",
    "max_tokens": 10,
    "messages": [{"role": "user", "content": "$PROMPT"}]
}
EOF
}

# ============================================================================
# 构建认证头
# ============================================================================
# 返回: 认证头字符串
# ----------------------------------------------------------------------------
api_build_auth_header() {
    echo "$AUTH_HEADER: $API_KEY"
}

# ============================================================================
# 解析 1308 错误，提取重置时间
# ============================================================================
# 参数:
#   $1 - API 响应内容
# 返回:
#   重置时间 (格式: YYYY-MM-DD HH:MM:SS) 或空字符串
# ----------------------------------------------------------------------------
api_parse_1308_error() {
    local response="$1"
    local reset_time=""

    # 尝试从响应中提取时间
    # 格式: "将在 2025-01-15 06:00:00 重置"
    reset_time=$(echo "$response" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)

    if [[ -n "$reset_time" ]]; then
        echo "$reset_time"
        return 0
    fi
    return 1
}

# ============================================================================
# 发送 API 请求
# ============================================================================
# 返回:
#   0 成功
#   1 失败（所有重试都失败）
#   2 配额不足（1308 错误）
# ----------------------------------------------------------------------------
api_send_request() {
    # 确保已设置消息
    api_set_prompt

    local url="$BASE_URL$ENDPOINT"
    local attempt=0
    local response http_code body
    local error_code=""

    log_info "开始唤醒 - 服务商: ${PROVIDER_NAME:-未知}"
    log_info_msg "正在唤醒 ${PROVIDER_NAME:-未知} ($MODEL)..."
    log_info_msg "发送提示词: ${PROMPT}"

    while (( attempt < MAX_RETRIES )); do
        ((attempt++))

        # 显示重试信息
        if [[ $attempt -gt 1 ]]; then
            echo -e "${YELLOW}第 $attempt 次尝试...${NC}"
        fi

        # 构建请求
        local auth_header
        auth_header="$(api_build_auth_header)"
        local headers=(-H "$auth_header" -H "Content-Type: $CONTENT_TYPE")

        if [[ -n "${API_VERSION_HEADER:-}" && -n "${API_VERSION:-}" ]]; then
            headers+=(-H "$API_VERSION_HEADER: $API_VERSION")
        fi

        # 发送请求
        response=$(curl -s -w "\n%{http_code}" \
            --max-time "$REQUEST_TIMEOUT" \
            "${headers[@]}" \
            -d "$(api_build_body)" \
            "$url" 2>&1) || true

        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')

        log_debug "HTTP 状态码: $http_code"
        log_debug "响应内容: $body"

        # 检查是否成功
        if [[ "$http_code" =~ ^2 ]]; then
            log_info "唤醒成功"
            log_success "唤醒成功 - ${PROVIDER_NAME:-未知} ($MODEL)"
            return 0
        fi

        # 检查是否是 1308 错误（配额不足）
        error_code=$(echo "$body" | jq -r '.error.code // empty' 2>/dev/null)

        if [[ "$error_code" == "1308" ]]; then
            local reset_time
            reset_time=$(api_parse_1308_error "$body")

            if [[ -n "$reset_time" ]]; then
                echo -e "${YELLOW}⚠ 错误码 1308: 配额不足${NC}"
                echo -e "${YELLOW}配额将在 $reset_time 重置${NC}"
                echo -e "${CYAN}已安排自动重试${NC}"
                log_warn "错误码 1308: 配额不足，将在 $reset_time 重置"

                # 导出重置时间供其他模块使用
                export API_RESET_TIME="$reset_time"
                return 2
            fi
        fi

        # 其他错误：显示详细信息并准备重试
        if (( attempt < MAX_RETRIES )); then
            if [[ -n "$error_code" ]]; then
                echo -e "${YELLOW}✗ 请求失败 (HTTP $http_code, 错误码: $error_code)${NC}"
                echo -e "${GRAY}等待 ${RETRY_DELAY} 秒后进行第 $((attempt + 1)) 次尝试...${NC}"
            else
                echo -e "${YELLOW}✗ 请求失败 (HTTP $http_code)${NC}"
                echo -e "${GRAY}等待 ${RETRY_DELAY} 秒后进行第 $((attempt + 1)) 次尝试...${NC}"
            fi
            log_warn "请求失败 (HTTP $http_code, 错误码: ${error_code:-无})，${RETRY_DELAY}秒后重试..."
            sleep "$RETRY_DELAY"
        fi
    done

    # 所有重试都失败
    log_error "唤醒失败 - HTTP $http_code (已重试 $MAX_RETRIES 次)"
    echo -e "${RED}✗ 唤醒失败${NC} - HTTP $http_code (已重试 $MAX_RETRIES 次)" >&2

    if [[ -n "$error_code" ]]; then
        echo -e "${GRAY}错误码: $error_code${NC}" >&2
    fi

    return 1
}

# ============================================================================
# 快速检查配额（不发送完整请求）
# ============================================================================
# 返回:
#   0 配额可用
#   1 配额不足或其他错误
# ----------------------------------------------------------------------------
api_check_quota() {
    local url="$BASE_URL$ENDPOINT"

    # 构建请求
    local auth_header
    auth_header="$(api_build_auth_header)"
    local headers=(-H "$auth_header" -H "Content-Type: $CONTENT_TYPE")

    # 发送最小请求
    local response
    response=$(curl -s -w "\n%{http_code}" \
        --max-time 10 \
        "${headers[@]}" \
        -d '{"model":"'"$MODEL"'","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
        "$url" 2>&1) || true

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    # 检查是否成功
    if [[ "$http_code" =~ ^2 ]]; then
        return 0
    fi

    # 检查是否是 1308 错误
    local error_code
    error_code=$(echo "$body" | jq -r '.error.code // empty' 2>/dev/null)

    if [[ "$error_code" == "1308" ]]; then
        return 1
    fi

    return 1
}
