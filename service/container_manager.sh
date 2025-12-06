#!/bin/bash
set -euo pipefail

# 配置项
WINDOW_WIDTH=120
WINDOW_HEIGHT=24
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
COMPOSE_FILE="/opt/app/conf/docker-compose.yml"

# 工具函数
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error_exit() {
    dialog --title "错误" --msgbox "操作失败：$1" 8 "$WINDOW_WIDTH"
    log "错误：$1"
    exit 1
}
confirm_action() {
    local msg="$1"
    dialog --title "确认操作" --yesno "$msg" 8 "$WINDOW_WIDTH"
}

# 检查docker-compose文件
check_compose_file() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        error_exit "未找到 docker-compose.yml：\n$COMPOSE_FILE\n请先部署应用或检查路径。"
    fi
}

# 获取并选择一个运行中的服务
select_running_service() {
    local temp_file="$TEMP_DIR/container_list.txt"
    docker-compose -f "$COMPOSE_FILE" ps --services | sort > "$temp_file"

    if [ ! -s "$temp_file" ]; then
        error_exit "当前没有运行中的服务容器。"
    fi

    local container_menu=()
    while IFS= read -r service; do
        container_menu+=("$service" "$service")
    done < "$temp_file"

    local selected_service
    selected_service=$(dialog --clear --title "选择服务" --menu "$1" \
        "$WINDOW_HEIGHT" "$WINDOW_WIDTH" "${#container_menu[@]}" \
        "${container_menu[@]}" \
        --stdout) || return 1 # 用户取消时返回非零值

    echo "$selected_service"
}

# 1. 查看容器状态
view_container_status() {
    log "查看容器状态"
    check_compose_file
    
    local temp_file="$TEMP_DIR/container_status.txt"
    local running_containers=$(docker-compose -f "$COMPOSE_FILE" ps -q)

    if [ -z "$running_containers" ]; then
        dialog --title "提示" --msgbox "当前应用栈无运行容器" 6 "$WINDOW_WIDTH"
        return
    fi

    echo "当前应用栈容器状态 (docker-compose.yml):" > "$temp_file"
    echo "========================================================================" >> "$temp_file"
    docker-compose -f "$COMPOSE_FILE" ps --format \
"ID: {{.ID}}
名称: {{.Names}}
镜像: {{.Image}}
状态: {{.Status}}
端口: {{.Ports}}
------------------------------------------------------------------------" >> "$temp_file" 2>&1

    dialog --title "容器运行详细状态" --textbox "$temp_file" "$WINDOW_HEIGHT" "$WINDOW_WIDTH"
}

# 2. 停止单个容器 (使用 docker-compose stop)
stop_container() {
    log "停止容器"
    check_compose_file
    
    local selected_service
    selected_service=$(select_running_service "请选择要停止的容器：") || return

    if ! confirm_action "确定要停止容器：$selected_service 吗？\n此操作会停止容器，但不会删除它。"; then
        dialog --title "操作取消" --msgbox "已取消停止容器 $selected_service" 6 "$WINDOW_WIDTH"
        return
    fi

    local temp_file="$TEMP_DIR/stop_log.txt"
    echo "执行：docker-compose stop $selected_service" > "$temp_file"
    echo "----------------------------------------" >> "$temp_file"
    
    if docker-compose -f "$COMPOSE_FILE" stop "$selected_service" >> "$temp_file" 2>&1; then
        dialog --title "成功" --msgbox "容器 $selected_service 已成功停止。" 6 "$WINDOW_WIDTH"
    else
        dialog --title "失败" --textbox "$temp_file" "$WINDOW_HEIGHT" "$WINDOW_WIDTH"
    fi
}

# 3. 重启单个容器 (使用 docker-compose restart)
restart_container() {
    log "重启容器"
    check_compose_file
    
    local selected_service
    selected_service=$(select_running_service "请选择要重启的容器：") || return

    if ! confirm_action "确定要重启容器：$selected_service 吗？\n此操作会先停止容器，然后再启动它。"; then
        dialog --title "操作取消" --msgbox "已取消重启容器 $selected_service" 6 "$WINDOW_WIDTH"
        return
    fi

    local temp_file="$TEMP_DIR/restart_log.txt"
    echo "执行：docker-compose restart $selected_service" > "$temp_file"
    echo "----------------------------------------" >> "$temp_file"
    
    if docker-compose -f "$COMPOSE_FILE" restart "$selected_service" >> "$temp_file" 2>&1; then
        dialog --title "成功" --msgbox "容器 $selected_service 已成功重启。" 6 "$WINDOW_WIDTH"
    else
        dialog --title "失败" --textbox "$temp_file" "$WINDOW_HEIGHT" "$WINDOW_WIDTH"
    fi
}

# 4. 进入容器终端
enter_container() {
    log "进入容器"
    check_compose_file
    
    local selected_service
    selected_service=$(select_running_service "请选择要进入的容器：") || return

    dialog --title "提示" --msgbox "即将进入容器：$selected_service\n退出容器请输入 'exit'。" 7 "$WINDOW_WIDTH"
    clear
    docker-compose -f "$COMPOSE_FILE" exec "$selected_service" /bin/sh
}

# 5. 停止并删除所有容器 (新增选项，使用 docker-compose down)
down_all_containers() {
    log "停止并删除所有容器"
    check_compose_file
    
    if ! confirm_action "警告：此操作将停止并删除所有服务容器！\n\n执行：docker-compose down\n\n说明：容器会被彻底删除，但数据卷和网络会被保留。\n\n确定要继续吗？"; then
        dialog --title "操作取消" --msgbox "已取消停止并删除所有容器。" 6 "$WINDOW_WIDTH"
        return
    fi

    local temp_file="$TEMP_DIR/down_log.txt"
    echo "执行：docker-compose down" > "$temp_file"
    echo "----------------------------------------" >> "$temp_file"
    
    if docker-compose -f "$COMPOSE_FILE" down >> "$temp_file" 2>&1; then
        dialog --title "成功" --msgbox "所有服务容器已成功停止并删除。" 6 "$WINDOW_WIDTH"
    else
        dialog --title "失败" --textbox "$temp_file" "$WINDOW_HEIGHT" "$WINDOW_WIDTH"
    fi
}

# 主菜单
main() {
    # 检查依赖
    if ! command -v docker > /dev/null; then
        error_exit "未安装 docker"
    fi
    if ! command -v docker-compose > /dev/null; then
        error_exit "未安装 docker-compose"
    fi

    while true; do
        local action
        action=$(dialog --clear --title "容器管理工具" --menu "请选择操作：" \
            "$WINDOW_HEIGHT" "$WINDOW_WIDTH" 6 \
            "1" "查看容器详细状态" \
            "2" "停止单个容器 (stop)" \
            "3" "重启单个容器 (restart)" \
            "4" "进入容器终端" \
            "5" "停止并删除所有容器 (down)" \
            "0" "退出" \
            --stdout) || break

        case "$action" in
            1) view_container_status ;;
            2) stop_container ;;
            3) restart_container ;;
            4) enter_container ;;
            5) down_all_containers ;;
            0) break ;;
            *) dialog --title "提示" --msgbox "无效选项，请重新选择" 6 "$WINDOW_WIDTH" ;;
        esac
    done

    dialog --title "再见" --msgbox "已退出容器管理工具。" 6 "$WINDOW_WIDTH"
}

# 入口
main
