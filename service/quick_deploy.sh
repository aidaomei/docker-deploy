#!/bin/bash

# --- 核心配置 ---
WORK_DIR="/opt/app/conf"
TEMPLATE_DIR="/opt/app/templates"
COMPOSE_FILE="$WORK_DIR/docker-compose.yml"
WINDOW_WIDTH=85
WINDOW_HEIGHT=22
DEBUG_LOG_FILE="/tmp/quick_deploy_debug.log"

# 确保工作目录存在
mkdir -p "$WORK_DIR"

# ==================== 工具函数 ====================
cleanup() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] 脚本退出，执行清理。" >> "$DEBUG_LOG_FILE"; }
trap cleanup EXIT
log_debug() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >> "$DEBUG_LOG_FILE"; }
error_exit() { dialog --title "致命错误" --msgbox "脚本执行失败: $1\n\n详细原因请查看调试日志: $DEBUG_LOG_FILE" 10 "$WINDOW_WIDTH"; log_debug "脚本因错误退出: $1"; exit 1; }
show_stage() { dialog --clear --title "$1" --msgbox "$2" 6 "$WINDOW_WIDTH"; }

# 1. 检查 Docker 服务状态
check_docker_status() {
    show_stage "步骤 1/5: 环境检查" "正在检查 Docker 服务状态..."
    log_debug "进入 check_docker_status 函数"
    
    if ! systemctl is-active --quiet docker; then
        dialog --title "Docker 服务未运行" --yesno "检测到 Docker 服务未运行。\n是否立即启动 Docker 服务？" 7 "$WINDOW_WIDTH"
        if [ $? -eq 0 ]; then
            log_debug "用户选择启动 Docker 服务"
            if ! sudo systemctl start docker; then error_exit "启动 Docker 服务失败！"; fi
            dialog --title "成功" --msgbox "Docker 服务已成功启动！" 6 "$WINDOW_WIDTH"
        else
            error_exit "用户取消启动 Docker 服务，部署流程终止。"
        fi
    else
        log_debug "Docker 服务正在运行"
        dialog --title "检查通过" --msgbox "Docker 服务正在运行。" 6 "$WINDOW_WIDTH"
    fi
}

# 2. 检查并处理配置文件
check_and_prepare_compose_file() {
    show_stage "步骤 2/5: 配置文件准备" "正在检查 docker-compose.yml 文件..."
    log_debug "进入 check_and_prepare_compose_file 函数"

    if [ ! -f "$COMPOSE_FILE" ]; then
        log_debug "未找到 docker-compose.yml 文件: $COMPOSE_FILE"
        dialog --title "配置文件缺失" --yesno "在工作目录 $WORK_DIR 中未找到 docker-compose.yml。\n是否从模板目录 $TEMPLATE_DIR 复制一套标准配置文件？" 8 "$WINDOW_WIDTH"
        if [ $? -eq 0 ]; then
            [ -f "$TEMPLATE_DIR/docker-compose.yml" ] || error_exit "模板文件 $TEMPLATE_DIR/docker-compose.yml 也不存在！"
            
            log_debug "开始从模板复制文件"
            cp -v "$TEMPLATE_DIR/docker-compose.yml" "$COMPOSE_FILE" >> "$DEBUG_LOG_FILE" 2>&1 || error_exit "复制 docker-compose.yml 失败！"
            
            if [ -f "$TEMPLATE_DIR/.env.example" ]; then
                cp -v "$TEMPLATE_DIR/.env.example" "$WORK_DIR/.env.example" >> "$DEBUG_LOG_FILE" 2>&1
                dialog --title "提示" --msgbox "模板环境变量文件已复制为 $WORK_DIR/.env.example。\n请根据需要修改后重命名为 .env。" 8 "$WINDOW_WIDTH"
            else
                dialog --title "提示" --msgbox "未找到 .env.example 模板。部署将使用 docker-compose.yml 中的默认值。" 7 "$WINDOW_WIDTH"
            fi
        else
            error_exit "用户取消复制模板文件，部署流程终止。"
        fi
    else
        log_debug "已找到配置文件: $COMPOSE_FILE"
        dialog --title "配置文件存在" --msgbox "已找到配置文件: $COMPOSE_FILE" 6 "$WINDOW_WIDTH"
    fi
}

# 3. 选择要部署的服务（单选+确认，100%可靠）
select_services() {
    show_stage "步骤 3/5: 服务选择" "正在动态提取服务列表..."
    log_debug "进入 select_services 函数"

    # 提取所有服务（逐行读取，确保每个服务名独立）
    log_debug "执行命令: docker compose -f \"$COMPOSE_FILE\" config --services"
    SERVICES_OUTPUT=$(docker compose -f "$COMPOSE_FILE" config --services 2>> "$DEBUG_LOG_FILE")
    
    if [ $? -ne 0 ]; then
        error_exit "提取服务列表失败！请检查 docker compose 命令和配置文件。"
    fi

    log_debug "命令 'docker compose config --services' 原始输出如下:"
    log_debug "--------------------------------------------------"
    log_debug "$SERVICES_OUTPUT"
    log_debug "--------------------------------------------------"

    # 构建服务数组和菜单（编号+服务名）
    local services=()
    local service_menu=()
    local counter=1
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            services+=("$line")
            service_menu+=("$counter" "$line")
            log_debug "添加服务到数组: 编号 $counter -> '$line'"
            ((counter++))
        fi
    done <<< "$SERVICES_OUTPUT"

    log_debug "最终构建的服务数组长度: ${#services[@]}"
    log_debug "最终构建的服务数组内容: ${services[@]}"

    if [ ${#services[@]} -eq 0 ]; then
        error_exit "未从配置文件中提取到任何服务！请检查配置文件语法。"
    fi

    # 第一步：选择单个服务（用--menu确保选择可靠）
    local selected_num
    selected_num=$(dialog --clear --title "选择服务" --menu "请选择要启动的服务（按Enter确认）:" \
        "$WINDOW_HEIGHT" "$WINDOW_WIDTH" "${#services[@]}" \
        "${service_menu[@]}" \
        --stdout)

    local dialog_exit_code=$?
    log_debug "第一步 dialog 退出码: $dialog_exit_code"
    log_debug "第一步 dialog 捕获的选择编号: '$selected_num'"

    if [ -z "$selected_num" ] || [ $dialog_exit_code -ne 0 ]; then
        log_debug "用户未选择服务，提示是否启动全部"
        dialog --title "选择无效" --yesno "你没有选择任何服务。\n是否要启动所有服务？" 7 "$WINDOW_WIDTH"
        if [ $? -eq 0 ]; then
            SERVICES_TO_START="${services[*]}"
            log_debug "用户选择启动所有服务: $SERVICES_TO_START"
        else
            error_exit "未选择任何服务，部署流程终止。"
        fi
    else
        # 第二步：确认选择的服务
        local selected_service="${services[$((selected_num - 1))]}"
        dialog --title "确认选择" --yesno "即将部署服务: $selected_service\n是否确认？" 7 "$WINDOW_WIDTH"
        if [ $? -eq 0 ]; then
            SERVICES_TO_START="$selected_service"
            log_debug "用户确认部署服务: $selected_service"
        else
            error_exit "用户取消部署，流程终止。"
        fi
    fi
    
    dialog --title "最终确认" --msgbox "即将部署以下服务: \n\n$SERVICES_TO_START" 8 "$WINDOW_WIDTH"
}

# 4. 执行部署
deploy_services() {
    show_stage "步骤 4/5: 开始部署" "正在启动选定的服务..."
    log_debug "进入 deploy_services 函数"
    log_debug "最终决定启动的服务: $SERVICES_TO_START"

    local deploy_cmd="(cd \"$WORK_DIR\" && docker compose up -d $SERVICES_TO_START)"
    log_debug "执行部署命令: $deploy_cmd"
    
    (eval "$deploy_cmd" 2>&1 | tee -a "$DEBUG_LOG_FILE") | dialog --title "部署服务" --gauge "正在执行部署，请稍候..." "$WINDOW_HEIGHT" "$WINDOW_WIDTH"

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        error_exit "服务部署命令执行失败！"
    fi

    dialog --title "部署成功" --msgbox "Docker Compose 已成功启动选定的服务。\n接下来将进行健康检查。" 7 "$WINDOW_WIDTH"
}

# 5. 健康检查（仅针对选定的服务，不影响其他服务）
health_check() {
    show_stage "步骤 5/5: 健康检查" "正在等待选定的服务进入健康状态..."
    log_debug "进入 health_check 函数"
    log_debug "需要检查健康状态的服务: $SERVICES_TO_START"

    # 仅遍历用户选定启动的服务
    local services=($SERVICES_TO_START)
    local max_attempts=12
    local attempt=1
    local all_healthy=false
    local temp_health_file=$(mktemp)  # 创建临时文件存储健康状态

    while [ $attempt -le $max_attempts ]; do
        all_healthy=true # 假设所有选定的服务都是健康的
        local health_status_msg="" # 用于存储状态信息
        
        for service in "${services[@]}"; do
            # 获取当前服务对应的容器ID（未启动的服务无容器ID）
            local container_id=$(docker compose -f "$COMPOSE_FILE" ps -q "$service")
            local status="未启动" # 未启动的服务状态为"未启动"
            
            if [ -n "$container_id" ]; then
                # 查询Docker维护的容器健康状态
                status=$(docker inspect --format '{{.State.Health.Status}}' "$container_id" 2>/dev/null)
                # 如果Docker未返回状态（如未定义健康检查），设为"运行中"
                [ -z "$status" ] && status="运行中"
            fi

            # 根据状态构建消息
            if [ "$status" = "healthy" ]; then
                health_status_msg+="✅ $service: 健康\n"
            elif [ "$status" = "running" ] || [ "$status" = "运行中" ]; then
                health_status_msg+="⚠️ $service: 运行中（无健康检查）\n"
                all_healthy=true # 无健康检查的服务，运行中即视为健康
            elif [ "$status" = "starting" ]; then
                health_status_msg+="❌ $service: 正在启动（健康检查中）\n"
                all_healthy=false # 仍在启动中，未达到健康状态
            else
                health_status_msg+="❌ $service: $status\n"
                all_healthy=false # 其他状态（如unhealthy、未启动），视为未健康
            fi
        done

        # 将健康状态写入临时文件并显示
        echo -e "健康检查: 第 $attempt/$max_attempts 次尝试\n\n$health_status_msg" > "$temp_health_file"
        dialog --title "服务健康状态" --textbox "$temp_health_file" "$WINDOW_HEIGHT" "$WINDOW_WIDTH"
        
        # 如果所有选定的服务都健康，退出循环
        if $all_healthy; then
            dialog --title "部署成功！" --msgbox "所有选定的服务都已达到健康状态！\n\n$health_status_msg" 10 "$WINDOW_WIDTH"
            rm -f "$temp_health_file"  # 清理临时文件
            return 0
        fi

        # 等待5秒后进行下一次检查
        attempt=$((attempt + 1))
        sleep 5
    done

    # 超时后清理临时文件并提示
    rm -f "$temp_health_file"
    dialog --title "健康检查超时" --msgbox "健康检查超时！部分选定的服务未达到健康状态。\n\n最后的健康状态：\n$health_status_msg" 12 "$WINDOW_WIDTH"
    return 1
}

# ==================== 主函数 ====================
main() {
    echo "=== Quick Deploy Script Debug Log ===" > "$DEBUG_LOG_FILE"
    echo "Script started at: $(date '+%Y-%m-%d %H:%M:%S')" >> "$DEBUG_LOG_FILE"
    echo "Work Dir: $WORK_DIR" >> "$DEBUG_LOG_FILE"
    echo "Compose File: $COMPOSE_FILE" >> "$DEBUG_LOG_FILE"
    echo "======================================" >> "$DEBUG_LOG_FILE"

    if ! command -v dialog >/dev/null 2>&1; then
        echo "错误: dialog 工具未安装。请先使用 'yum install -y dialog' 安装。"
        exit 1
    fi
    if ! command -v docker >/dev/null 2>&1; then
        error_exit "未找到 docker 命令，请检查 Docker 是否已安装。"
    fi
    if ! docker compose version >/dev/null 2>&1; then
        error_exit "未找到 'docker compose' 命令，请确认 Docker Compose V2 已正确安装。"
    fi

    check_docker_status
    check_and_prepare_compose_file
    select_services
    deploy_services
    health_check

    log_debug "快速部署流程正常结束"
}

# 入口点
main
