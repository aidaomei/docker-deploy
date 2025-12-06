#!/bin/sh

# ==================== 基础函数与全局配置 ====================
# 终端重置函数（保留原有逻辑）
reset_terminal() {
    stty sane || true
    reset || true
    clear
}

# 检查并自动安装 dialog 工具（保留原有逻辑）
prepare_dialog() {
    if ! command -v dialog >/dev/null 2>&1; then
        echo "=== 检测到系统未安装 dialog 工具，开始自动安装 ==="
        
        if [ "$(id -u)" -ne 0 ]; then
            echo "错误：安装 dialog 需要 root 权限，请使用 sudo 重新运行脚本！"
            echo "  sudo $0"
            exit 1
        fi

        if [ -f "/etc/yum.repos.d/CentOS-Base.repo" ]; then
            mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak || {
                echo "备份原有 yum 源失败，请检查 /etc/yum.repos.d/ 目录权限！"
                exit 1
            }
        fi
        curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo || {
            echo "下载阿里云 yum 源失败，请检查网络连接！"
            exit 1
        }

        yum clean all && yum makecache || {
            echo "yum 缓存处理失败，请手动执行：yum clean all && yum makecache"
            exit 1
        }
        yum install -y dialog || {
            echo "安装 dialog 失败，请手动执行：yum install -y dialog"
            exit 1
        }

        echo "=== dialog 安装完成，环境准备就绪 ==="
    fi
}

# 全局统一配置（保留原有逻辑，新增 CHECK_ENV_SCRIPT 路径）
WINDOW_WIDTH=85
MENU_HEIGHT=20
MSGBOX_HEIGHT=10
TOOL_ROOT="/root/service"
CONTAINER_MANAGER_SCRIPT="${TOOL_ROOT}/container_manager.sh"
ROLLBACK_SCRIPT="${TOOL_ROOT}/rollback.sh"
LOGS_SCRIPT="${TOOL_ROOT}/logs.sh"
CUSTOM_DEPLOY_SCRIPT="/root/service/custom_deploy/custom_deploy_menu.sh"
QUICK_DEPLOY_SCRIPT="/root/service/quick_deploy.sh"
# 新增：环境检查脚本路径（与 check_env.sh 实际位置一致）
CHECK_ENV_SCRIPT="${TOOL_ROOT}/check_env.sh"

# 工具函数：错误退出（保留原有逻辑）
error_exit() {
    if [ -n "$(command -v dialog)" ]; then
        dialog --title "错误" --msgbox "操作失败：$1" 8 60
    else
        echo "错误：$1" >&2
    fi
    exit 1
}

# ==================== 功能模块实现（修改 check_environment 函数） ====================
# 1. 环境检查（修改为调用 check_env.sh 并显示输出）
check_environment() {
    # 检查 check_env.sh 是否存在且可执行
    if [ ! -f "$CHECK_ENV_SCRIPT" ]; then
        dialog --title "错误" --msgbox "环境检查脚本不存在！\n路径：$CHECK_ENV_SCRIPT\n请先创建该脚本后重试。" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi
    if [ ! -x "$CHECK_ENV_SCRIPT" ]; then
        dialog --title "错误" --msgbox "环境检查脚本无执行权限！\n请先添加权限：chmod +x $CHECK_ENV_SCRIPT" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi

    # 执行 check_env.sh 并将输出保存到临时文件
    local temp_check_log=$(mktemp -t check_env.XXXXXX.log)
    "$CHECK_ENV_SCRIPT" > "$temp_check_log" 2>&1
    local check_result=$?

    # 将 check_env.sh 的输出显示在 dialog 窗口中
    dialog --title "环境检查报告" --textbox "$temp_check_log" 25 $WINDOW_WIDTH

    # 根据 check_env.sh 的退出码判断结果
    if [ "$check_result" -eq 0 ]; then
        dialog --title "环境检查通过" --msgbox "✅ 所有检查项均达标，可正常执行后续操作！" 6 $WINDOW_WIDTH
    else
        dialog --title "环境检查未通过" --msgbox "❌ 存在异常项，请根据报告解决问题后重试。" 6 $WINDOW_WIDTH
    fi

    # 删除临时文件
    rm -f "$temp_check_log"
    return $check_result
}

# 2. 自定义部署（保留原有逻辑）
custom_deploy() {
    if [ ! -f "$CUSTOM_DEPLOY_SCRIPT" ]; then
        dialog --title "错误 - 子脚本缺失" --msgbox "自定义部署子菜单脚本不存在！\n\n路径：$CUSTOM_DEPLOY_SCRIPT\n\n请先创建该脚本并配置功能后重试。" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi
    if [ ! -x "$CUSTOM_DEPLOY_SCRIPT" ]; then
        dialog --title "错误 - 权限不足" --msgbox "自定义部署子菜单脚本无执行权限！\n\n请先添加执行权限：\n  chmod +x $CUSTOM_DEPLOY_SCRIPT" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi

    dialog --title "自定义部署（核心）" --msgbox "即将进入自定义部署子菜单...\n\n功能说明：支持镜像拉取、配置编写、模板修改（docker-compose.yml / config.env）。" 8 $WINDOW_WIDTH
    "$CUSTOM_DEPLOY_SCRIPT"
    dialog --title "自定义部署完成" --msgbox "自定义部署操作已结束，返回主菜单。" 6 $WINDOW_WIDTH
    return 0
}

# 3. 快速部署（保留原有逻辑）
quick_deploy() {
    if [ ! -f "$QUICK_DEPLOY_SCRIPT" ]; then
        dialog --title "错误 - 脚本缺失" --msgbox "快速部署脚本不存在！\n\n路径：$QUICK_DEPLOY_SCRIPT\n\n请先创建该脚本并配置功能后重试。" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi
    if [ ! -x "$QUICK_DEPLOY_SCRIPT" ]; then
        dialog --title "错误 - 权限不足" --msgbox "快速部署脚本无执行权限！\n\n请先添加执行权限：\n  chmod +x $QUICK_DEPLOY_SCRIPT" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi

    dialog --title "快速部署（模板）" --msgbox "即将进入快速部署流程...\n\n功能说明：基于模板一键上线，配置存储于 /opt/app/conf。\n\n部署过程将在当前终端显示，完成后按任意键返回。" 9 $WINDOW_WIDTH
    
    clear
    "$QUICK_DEPLOY_SCRIPT"
    
    echo -e "\n按任意键返回主菜单..."
    read -n 1 -s
    
    reset_terminal
    return 0
}

# 4. 容器管理（保留原有逻辑）
container_management() {
    if [ ! -f "$CONTAINER_MANAGER_SCRIPT" ]; then
        dialog --title "错误 - 脚本缺失" --msgbox "容器管理脚本不存在！\n\n路径：$CONTAINER_MANAGER_SCRIPT\n\n请先创建该脚本并配置功能后重试。" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi
    if [ ! -x "$CONTAINER_MANAGER_SCRIPT" ]; then
        dialog --title "错误 - 权限不足" --msgbox "容器管理脚本无执行权限！\n\n请先添加执行权限：\n  chmod +x $CONTAINER_MANAGER_SCRIPT" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi

    dialog --title "容器管理" --msgbox "即将进入容器管理工具...\n\n功能说明：支持容器状态查看、停止、重启及进入容器终端。\n\n按任意键进入..." 8 $WINDOW_WIDTH
    clear
    "$CONTAINER_MANAGER_SCRIPT"
    
    reset_terminal
    return 0
}

# 5. 版本回滚（保留原有逻辑）
version_rollback() {
    if [ ! -f "$ROLLBACK_SCRIPT" ]; then
        dialog --title "错误 - 脚本缺失" --msgbox "版本回滚脚本不存在！\n\n路径：$ROLLBACK_SCRIPT\n\n请先创建该脚本并配置功能后重试。" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi
    if [ ! -x "$ROLLBACK_SCRIPT" ]; then
        dialog --title "错误 - 权限不足" --msgbox "版本回滚脚本无执行权限！\n\n请先添加执行权限：\n  chmod +x $ROLLBACK_SCRIPT" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi

    dialog --title "版本回滚（2.0）" --msgbox "即将进入版本回滚工具...\n\n功能说明：\n  1. 自动检测可用镜像版本（按创建时间倒序）\n  2. 支持配置文件自动备份（路径：/opt/app/conf/backups）\n  3. 实时显示回滚进度日志\n  4. 回滚后自动验证容器状态\n\n按任意键进入..." 12 $WINDOW_WIDTH
    
    clear
    "$ROLLBACK_SCRIPT"
    
    reset_terminal
    dialog --title "回滚操作结束" --msgbox "版本回滚工具已退出，返回主菜单。\n\n如需查看回滚日志，可访问：/tmp/rollback_live.log" 7 $WINDOW_WIDTH
    return 0
}

# 6. 日志查看（保留原有逻辑）
log_viewer() {
    if [ ! -f "$LOGS_SCRIPT" ]; then
        dialog --title "错误 - 脚本缺失" --msgbox "日志查看脚本不存在！\n\n路径：$LOGS_SCRIPT\n\n请先创建该脚本并配置功能后重试。" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi
    if [ ! -x "$LOGS_SCRIPT" ]; then
        dialog --title "错误 - 权限不足" --msgbox "日志查看脚本无执行权限！\n\n请先添加执行权限：\n  chmod +x $LOGS_SCRIPT" $MSGBOX_HEIGHT $WINDOW_WIDTH
        return 1
    fi

    dialog --title "日志查看" --msgbox "即将进入日志查看工具...\n\n功能说明：支持选择容器查看实时日志，按 Ctrl+C 可退出当前日志查看，返回容器选择菜单。\n\n按任意键进入..." 8 $WINDOW_WIDTH
    clear
    "$LOGS_SCRIPT"
    
    reset_terminal
    dialog --title "日志查看结束" --msgbox "日志查看工具已退出，返回主菜单。" 6 $WINDOW_WIDTH
    return 0
}

# ==================== 主菜单入口（保留原有逻辑） ====================
show_main_menu() {
    local tempfile=$(mktemp -t dialog.XXXXXX)
    trap "rm -f $tempfile; reset_terminal" EXIT

    while true; do
        # 显示主菜单（原有逻辑不变）
        dialog --clear --title "Docker 容器化管理工具 V2.2" \
            --menu "脚本目录：$TOOL_ROOT | 部署目录：/opt/app/conf\n\n请选择功能模块：" $MENU_HEIGHT $WINDOW_WIDTH 7 \
            "1" "环境检查 - 安装依赖/解决端口冲突（前置保障）" \
            "2" "自定义部署（核心）- 镜像拉取/配置编写/模板修改" \
            "3" "快速部署（模板）- 独立目录一键上线（不干扰现有部署）" \
            "4" "容器管理 - 状态/停止/重启/进入容器（集成工具）" \
            "5" "版本回滚（2.0）- 交互式选择/自动备份/实时日志" \
            "6" "日志查看 - 容器实时日志一站式查看（支持连续查看）" \
            "0" "退出工具" 2>"$tempfile"
        
        local exit_code=$?
        if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 255 ]; then
            dialog --title "确认退出" --yesno "是否确定退出 Docker 容器化管理工具？" 7 $WINDOW_WIDTH
            if [ $? -eq 0 ]; then
                break
            else
                continue
            fi
        fi

        # 执行选中的功能（原有逻辑不变）
        local choice=$(cat "$tempfile")
        case "$choice" in
            "1") check_environment ;;  # 仅选项1调用环境检查
            "2") custom_deploy ;;
            "3") quick_deploy ;;
            "4") container_management ;;
            "5") version_rollback ;;
            "6") log_viewer ;;
            "0") break ;;
            *) dialog --title "错误" --msgbox "无效选择，请重试！" 6 $WINDOW_WIDTH ;;
        esac
    done

    dialog --title "再见" --msgbox "感谢使用 Docker 容器化管理工具 V2.2，下次再见！" 6 $WINDOW_WIDTH
    reset_terminal
}

# ==================== 脚本启动入口（保留原有逻辑） ====================
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

prepare_dialog
show_main_menu
