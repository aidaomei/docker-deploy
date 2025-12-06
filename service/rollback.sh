#!/bin/bash
set -euo pipefail

# ==================== 配置区（可根据实际环境调整） ====================
COMPOSE_FILE="/opt/app/conf/docker-compose.yml"       # docker-compose配置文件路径
SERVICE_NAME="backend"                           # 要回滚的服务名（需与docker-compose.yml中一致）
BACKEND_IMAGE="java-backend-app"                 # 后端镜像名（用于过滤镜像标签）
BACKUP_DIR="/opt/app/conf/backups"               # 配置备份目录（自动创建）
LOG_FILE="/tmp/rollback_live.log"                # 回滚实时日志文件
TEMP_FILE=$(mktemp -t rollback.XXXXXX)           # 临时文件（存储用户选择）
trap 'rm -f "$TEMP_FILE"' EXIT                   # 脚本退出时清理临时文件

# ==================== 辅助函数 ====================
# 1. 检查依赖（docker、docker-compose）
check_dependencies() {
    local missing=()
    if ! command -v docker >/dev/null 2>&1; then
        missing+=("docker")
    fi
    if ! command -v docker-compose >/dev/null 2>&1; then
        missing+=("docker-compose")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        dialog --title "依赖检查失败" --msgbox "以下工具未安装，请先安装后重试：\n\n${missing[*]}" 8 60
        exit 1
    fi
}

# 2. 检查docker-compose文件是否存在
check_compose_file() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        dialog --title "配置文件缺失" --msgbox "未找到 docker-compose.yml 文件！\n\n路径：$COMPOSE_FILE" 7 60
        exit 1
    fi
}

# 3. 初始化备份目录
init_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR" || {
            dialog --title "备份目录创建失败" --msgbox "无法创建备份目录：$BACKUP_DIR" 7 60
            exit 1
        }
    fi
}

# 4. 获取可回滚的版本标签（按镜像创建时间倒序，最新在前）
get_available_versions() {
    # 过滤指定服务的镜像标签，排除<none>标签，按创建时间倒序
    docker images --filter "reference=${BACKEND_IMAGE}" --format "{{.Tag}}" \
        | grep -v "<none>" | sort -r
}

# 5. 实时显示回滚日志（配合dialog的tailbox组件）
show_live_log() {
    dialog --title "回滚实时日志" --tailbox "$LOG_FILE" 20 85
}

# 6. 清理旧日志
clean_old_log() {
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE" || true
    fi
    touch "$LOG_FILE" || {
        dialog --title "日志文件创建失败" --msgbox "无法创建日志文件：$LOG_FILE" 7 60
        exit 1
    }
}

# ==================== 核心功能模块 ====================
# 1. 版本选择菜单
select_version() {
    local versions=$(get_available_versions)
    if [ -z "$versions" ]; then
        dialog --title "无可用版本" --msgbox "未检测到 ${BACKEND_IMAGE} 的有效镜像标签，请先部署版本后重试。" 8 60
        exit 1
    fi

    # 构建dialog菜单选项（序号+标签）
    local menu_items=()
    local counter=1
    while IFS= read -r tag; do
        menu_items+=("$counter" "$tag")
        ((counter++))
    done <<< "$versions"

    # 显示版本选择菜单
    dialog --clear --title "版本回滚 - 选择目标版本" \
        --menu "请选择要回滚的 ${SERVICE_NAME} 服务版本（按创建时间倒序）：" \
        15 60 8 \
        "${menu_items[@]}" \
        2>"$TEMP_FILE"

    # 处理用户选择（0=选择，1=取消，255=ESC）
    local exit_code=$?
    if [ $exit_code -eq 1 ] || [ $exit_code -eq 255 ]; then
        dialog --title "操作取消" --msgbox "已取消版本回滚操作。" 6 50
        exit 0
    fi

    # 获取用户选择的目标标签
    local selected_idx=$(cat "$TEMP_FILE")
    target_tag=$(echo "$versions" | sed -n "${selected_idx}p")
    if [ -z "$target_tag" ]; then
        dialog --title "选择无效" --msgbox "无效的版本选择，请重新操作。" 6 50
        exit 1
    fi
}

# 2. 执行回滚（核心逻辑）
execute_rollback() {
    local target_tag=$1
    local backup_file="${BACKUP_DIR}/docker-compose.yml.$(date +%Y%m%d%H%M%S).bak"

    # 初始化日志和备份目录
    clean_old_log
    init_backup_dir

    # 写入回滚开始日志
    echo "=== 版本回滚开始（$(date +'%Y-%m-%d %H:%M:%S')） ===" >> "$LOG_FILE"
    echo "目标服务：$SERVICE_NAME" >> "$LOG_FILE"
    echo "目标镜像：$BACKEND_IMAGE:$target_tag" >> "$LOG_FILE"
    echo "配置文件：$COMPOSE_FILE" >> "$LOG_FILE"
    echo "备份文件：$backup_file" >> "$LOG_FILE"
    echo "----------------------------------------" >> "$LOG_FILE"

    # 备份当前配置文件
    echo "正在备份当前 docker-compose.yml 文件..." >> "$LOG_FILE"
    cp -a "$COMPOSE_FILE" "$backup_file" || {
        echo "错误：配置文件备份失败！" >> "$LOG_FILE"
        dialog --title "回滚失败" --msgbox "配置文件备份失败，请检查 $BACKUP_DIR 权限。\n\n详细日志：$LOG_FILE" 8 60
        exit 1
    }
    echo "配置文件备份成功：$backup_file" >> "$LOG_FILE"

    # 修改docker-compose.yml中的镜像标签
    echo "正在修改镜像标签（当前->目标：${BACKEND_IMAGE}:* -> ${BACKEND_IMAGE}:${target_tag}）..." >> "$LOG_FILE"
    sed -i.bak "s|${BACKEND_IMAGE}:[^ ]*|${BACKEND_IMAGE}:${target_tag}|g" "$COMPOSE_FILE" || {
        echo "错误：配置文件修改失败！正在恢复备份..." >> "$LOG_FILE"
        mv -f "$COMPOSE_FILE.bak" "$COMPOSE_FILE" || true
        dialog --title "回滚失败" --msgbox "配置文件修改失败，已恢复原配置。\n\n详细日志：$LOG_FILE" 8 60
        exit 1
    }
    rm -f "$COMPOSE_FILE.bak" || true  # 清理sed备份文件
    echo "镜像标签修改成功" >> "$LOG_FILE"

    # 重启容器生效
    echo "正在重启容器应用新版本..." >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_FILE" down >> "$LOG_FILE" 2>&1 || {
        echo "错误：容器停止失败！" >> "$LOG_FILE"
        dialog --title "回滚失败" --msgbox "容器停止失败，请手动检查容器状态。\n\n详细日志：$LOG_FILE" 8 60
        exit 1
    }
    docker-compose -f "$COMPOSE_FILE" up -d >> "$LOG_FILE" 2>&1 || {
        echo "错误：容器启动失败！正在恢复备份..." >> "$LOG_FILE"
        mv -f "$backup_file" "$COMPOSE_FILE" || true
        dialog --title "回滚失败" --msgbox "容器启动失败，已恢复原配置。\n\n详细日志：$LOG_FILE" 8 60
        exit 1
    }
    echo "容器重启成功" >> "$LOG_FILE"

    # 验证回滚结果
    echo "正在验证回滚结果..." >> "$LOG_FILE"
    local container_status=$(docker-compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | grep -w "$SERVICE_NAME")
    if [ -z "$container_status" ]; then
        echo "错误：回滚验证失败！容器未正常运行。" >> "$LOG_FILE"
        dialog --title "回滚失败" --msgbox "容器未正常运行，回滚可能失败。\n\n详细日志：$LOG_FILE" 8 60
        exit 1
    fi

    # 写入回滚成功日志
    echo "----------------------------------------" >> "$LOG_FILE"
    echo "=== 版本回滚成功（$(date +'%Y-%m-%d %H:%M:%S')） ===" >> "$LOG_FILE"
    echo "当前运行版本：$BACKEND_IMAGE:$target_tag" >> "$LOG_FILE"
    echo "容器状态：正常运行" >> "$LOG_FILE"
}

# ==================== 主流程 ====================
main() {
    # 前置检查
    check_dependencies
    check_compose_file

    # 版本选择
    select_version
    dialog --title "确认回滚" --yesno "确定要将 ${SERVICE_NAME} 服务回滚到版本：\n\n${BACKEND_IMAGE}:${target_tag}\n\n回滚过程将重启容器，可能导致服务短暂中断，是否继续？" 10 60
    if [ $? -ne 0 ]; then
        dialog --title "操作取消" --msgbox "已取消版本回滚操作。" 6 50
        exit 0
    fi

    # 执行回滚（后台运行，前台显示实时日志）
    execute_rollback "$target_tag" &
    show_live_log  # 实时显示日志

    # 回滚完成提示
    dialog --title "回滚成功" --msgbox "版本回滚已完成！\n\n目标版本：${BACKEND_IMAGE}:${target_tag}\n\n详细日志：$LOG_FILE\n\n容器状态：正常运行" 10 60
}

# ==================== 脚本入口 ====================
main
