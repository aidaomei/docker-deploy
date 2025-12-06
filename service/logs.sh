#!/bin/bash
set -euo pipefail

# 配置项（与docker-compose路径一致）
COMPOSE_FILE="/opt/app/conf/docker-compose.yml"
LOG_FILE="/tmp/logs_live.log"  # 实时日志文件
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# 工具函数
error_exit() {
    if [ -n "$(command -v dialog)" ]; then
        dialog --title "错误" --msgbox "操作失败：$1" 8 60
    else
        echo "错误：$1" >&2
    fi
    exit 1
}

# 检查 docker-compose.yml 存在
check_compose() {
    if [ ! -f "${COMPOSE_FILE}" ]; then
        error_exit "未找到 ${COMPOSE_FILE}"
    fi
}

# 模式1：输出可用容器名（每次查看前重新获取，支持动态容器变化）
list_containers() {
    check_compose
    local containers=$(docker-compose -f "${COMPOSE_FILE}" ps --services 2>/dev/null)
    if [ -z "$containers" ]; then
        error_exit "未检测到运行中的容器"
    fi
    echo "$containers"
}

# 模式2：查看指定容器日志（查看完后返回菜单，不退出）
view_logs() {
    local CONTAINER_NAME=$1
    # 清空日志文件，避免残留之前的日志
    > "${LOG_FILE}"
    
    # 检查容器状态
    local container_status=$(docker-compose -f "${COMPOSE_FILE}" ps --format "{{.Name}}\t{{.Status}}" "${CONTAINER_NAME}" 2>/dev/null)
    if [ -z "$container_status" ]; then
        dialog --title "警告" --msgbox "容器 ${CONTAINER_NAME} 不存在或已停止，返回菜单..." 6 60
        return  # 仅返回，不退出脚本
    fi
    echo "容器状态：${container_status}" > "${LOG_FILE}"
    echo "正在查看 ${CONTAINER_NAME} 实时日志（按 Ctrl+C 退出当前日志查看，返回菜单）..." >> "${LOG_FILE}"

    # 后台执行日志命令，写入文件
    docker-compose -f "${COMPOSE_FILE}" logs -f "${CONTAINER_NAME}" >> "${LOG_FILE}" 2>&1 &
    local log_pid=$!

    # 显示实时日志，用户按Ctrl+C后退出当前查看
    dialog --title "实时日志 - ${CONTAINER_NAME}" --tailbox "${LOG_FILE}" 25 80
    kill "$log_pid" 2>/dev/null || true  # 终止当前容器的日志进程
}

# 交互式菜单（循环显示，支持连续选择）
main() {
    if [ -z "$(command -v dialog)" ]; then
        error_exit "未安装 dialog 工具，请先执行：yum install -y dialog"
    fi

    while true; do  # 循环菜单，直到用户Cancel
        # 每次循环重新获取容器列表（支持容器动态变化）
        local containers=$(list_containers)
        local container_menu=()
        local counter=1

        # 构建容器选择菜单
        while IFS= read -r container; do
            container_menu+=("$counter" "$container")
            ((counter++))
        done <<< "$containers"

        # 显示容器选择菜单
        local selected_idx
        selected_idx=$(dialog --clear --title "选择容器日志（可连续查看）" --menu "请选择要查看日志的容器，按 Cancel 退出：" \
            15 60 5 \
            "${container_menu[@]}" \
            --stdout)
        
        # 处理用户操作：Cancel 则退出循环（退出日志查看）
        local exit_code=$?
        if [ $exit_code -eq 1 ] || [ $exit_code -eq 255 ]; then
            dialog --title "提示" --msgbox "已退出日志查看功能" 6 60
            break  # 跳出循环，结束脚本
        fi

        # 根据选择的序号获取容器名，执行日志查看
        local selected_container=$(echo "$containers" | sed -n "${selected_idx}p")
        view_logs "$selected_container"
    done
}

# 入口：区分参数模式和交互式模式
if [ $# -eq 1 ]; then
    if [ "$1" = "list" ]; then
        list_containers
    else
        view_logs "$1"
    fi
else
    main
fi
