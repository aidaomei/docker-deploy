#!/bin/sh

reset_terminal() {
    stty sane || true
    reset || true
    clear
}

CONF_DIR="/opt/app/conf"
SCRIPT_CONF_FILE="${CONF_DIR}/custom_deploy.conf"

mkdir -p "${CONF_DIR}" "/opt/app/workspace" && chmod 755 "${CONF_DIR}" "/opt/app/workspace"

if [ ! -f "${SCRIPT_CONF_FILE}" ]; then
    cat << 'CONF_EOF' > "${SCRIPT_CONF_FILE}"
WORKSPACE="/opt/app/workspace"
CONF_DIR="/opt/app/conf"
CONF_EOF
    chmod 644 "${SCRIPT_CONF_FILE}"
fi

. "${SCRIPT_CONF_FILE}"

WINDOW_WIDTH=85
MENU_HEIGHT=15
CURRENT_DIR=$(cd $(dirname $0); pwd)
PULL_SCRIPT="${CURRENT_DIR}/image_pull.sh"
BUILD_SCRIPT="${CURRENT_DIR}/image_build.sh"
USER_HOME=$(eval echo ~${USER})  # 兼容 sudo 切换用户的场景

handle_image_pull() {
    local image_name tag temp_file choice selected_tag
    temp_file=$(mktemp -t dialog.XXXXXX)
    
    dialog --clear --title "输入镜像名" --inputbox "请输入要拉取的镜像名（例如：nginx, mysql）:" ${MENU_HEIGHT} ${WINDOW_WIDTH} 2>"${temp_file}"
    local exit_code=$?
    if [ ${exit_code} -ne 0 ] || [ -z "$(cat ${temp_file})" ]; then
        rm -f "${temp_file}"
        [ ${exit_code} -eq 0 ] && dialog --title "错误" --msgbox "镜像名不能为空！" ${MENU_HEIGHT} ${WINDOW_WIDTH}
        return
    fi
    image_name=$(cat "${temp_file}" | tr 'A-Z' 'a-z')
    rm -f "${temp_file}"

    dialog --clear --title "输入标签" --inputbox "请输入标签（例如：latest），直接回车将获取推荐标签:" ${MENU_HEIGHT} ${WINDOW_WIDTH} 2>"${temp_file}"
    exit_code=$?
    if [ ${exit_code} -ne 0 ]; then
        rm -f "${temp_file}"
        return
    fi
    tag=$(cat "${temp_file}")
    rm -f "${temp_file}"

    temp_file=$(mktemp -t pull_output.XXXXXX)
    if [ -n "${tag}" ]; then
        dialog --title "拉取进度" --tailbox "${temp_file}" ${MENU_HEIGHT} ${WINDOW_WIDTH} &
        local tail_pid=$!
        "${PULL_SCRIPT}" "${image_name}" "${tag}" > "${temp_file}" 2>&1
        local pull_exit_code=$?
        kill ${tail_pid} >/dev/null 2>&1
        wait ${tail_pid} >/dev/null 2>&1
        if [ ${pull_exit_code} -eq 0 ]; then
            dialog --title "成功" --msgbox "镜像 \`${image_name}:${tag}\` 拉取并打标完成！" ${MENU_HEIGHT} ${WINDOW_WIDTH}
        else
            dialog --title "失败" --msgbox "拉取镜像 \`${image_name}:${tag}\` 失败！\n\n详细信息：\n$(cat "${temp_file}")" $((MENU_HEIGHT + 5)) ${WINDOW_WIDTH}
        fi
    else
        "${PULL_SCRIPT}" "${image_name}" > "${temp_file}" 2>&1
        local pull_exit_code=$?
        if [ ${pull_exit_code} -eq 0 ]; then
            dialog --clear --title "选择推荐标签" --menu "请选择要拉取的标签（${image_name}）:" ${MENU_HEIGHT} ${WINDOW_WIDTH} 10 $(cat "${temp_file}" | awk '{print $1 " \"" $2 " - " substr($0, index($0,$3)) "\""}') 2>"${temp_file%.log}.choice"
            exit_code=$?
            if [ ${exit_code} -ne 0 ]; then
                rm -f "${temp_file}" "${temp_file%.log}.choice"
                return
            fi
            choice=$(cat "${temp_file%.log}.choice")
            selected_tag=$(cat "${temp_file}" | awk -v c="${choice}" '$1 == c {print $2}')
            dialog --title "拉取进度" --tailbox "${temp_file}" ${MENU_HEIGHT} ${WINDOW_WIDTH} &
            local tail_pid=$!
            "${PULL_SCRIPT}" "${image_name}" "${selected_tag}" > "${temp_file}" 2>&1
            pull_exit_code=$?
            kill ${tail_pid} >/dev/null 2>&1
            wait ${tail_pid} >/dev/null 2>&1
            if [ ${pull_exit_code} -eq 0 ]; then
                dialog --title "成功" --msgbox "镜像 \`${image_name}:${selected_tag}\` 拉取并打标完成！" ${MENU_HEIGHT} ${WINDOW_WIDTH}
            else
                dialog --title "失败" --msgbox "拉取镜像 \`${image_name}:${selected_tag}\` 失败！\n\n详细信息：\n$(cat "${temp_file}")" $((MENU_HEIGHT + 5)) ${WINDOW_WIDTH}
            fi
        else
            dialog --title "错误" --msgbox "获取 \`${image_name}\` 推荐标签失败！\n\n详细信息：\n$(cat "${temp_file}")" $((MENU_HEIGHT + 5)) ${WINDOW_WIDTH}
        fi
    fi
    rm -f "${temp_file}" "${temp_file%.log}.choice" 2>/dev/null
}

handle_config_edit_upload() {
    local temp_sub=$(mktemp -t config_sub.XXXXXX)
    trap "rm -f ${temp_sub}" EXIT

    while true; do
        dialog --clear --title "配置编写功能（配置文件存储：${CONF_DIR}）" \
            --menu "请选择操作类型：" ${MENU_HEIGHT} ${WINDOW_WIDTH} 3 \
            "1" "在线编辑配置文件（vi编辑）" \
            "2" "上传本地配置文件/目录（列表选择）" \
            "0" "返回子菜单" 2>"${temp_sub}"
        
        local exit_code=$?
        if [ ${exit_code} -ne 0 ]; then
            break
        fi

        local config_choice=$(cat "${temp_sub}")
        case "${config_choice}" in
            "1")
                local file_list=()
                local counter=1
                for file in "${CONF_DIR}"/*; do
                    [ -f "${file}" ] && file_list+=("$counter" "$(basename "${file}")") && ((counter++))
                done
                file_list+=("$counter" "[创建新文件]")

                local choice
                choice=$(dialog --clear --title "选择要编辑的文件（${CONF_DIR}）" --menu "↑↓选择，Enter确认（vi编辑）:" 15 60 10 "${file_list[@]}" --stdout)
                [ -z "${choice}" ] && continue

                local edit_file
                if [ "${choice}" -eq "${counter}" ]; then
                    edit_file=$(dialog --clear --title "创建新文件" --inputbox "输入文件名（例如：docker-compose.yml）:" 8 50 --stdout)
                    [ -z "${edit_file}" ] && continue
                    edit_file="${CONF_DIR}/${edit_file}"
                    touch "${edit_file}"
                    chmod 644 "${edit_file}"
                else
                    local index=$(( (choice - 1) * 2 + 1 ))
                    edit_file="${CONF_DIR}/${file_list[$index]}"
                fi

                vi "${edit_file}"
                dialog --title "编辑完成" --msgbox "文件 ${edit_file} 编辑会话结束。" 6 50
                ;;

            "2")
                local local_dir="$HOME"
                local upload_choice=""
                
                while true; do
                    local item_list=()
                    local counter=1
                    # 构建文件/目录列表
                    for item in "${local_dir}"/*; do
                        if [ -f "${item}" ]; then
                            item_list+=("$counter" "文件: $(basename "${item}")")
                        elif [ -d "${item}" ]; then
                            item_list+=("$counter" "目录: $(basename "${item}")")
                        fi
                        ((counter++))
                    done
                    
                    # 记录两个功能选项的编号（关键：先存编号，再自增counter）
                    local back_to_parent_idx=$counter  # 返回上级的编号
                    item_list+=("$back_to_parent_idx" "[返回上级目录]")
                    ((counter++))
                    local cancel_upload_idx=$counter   # 取消上传的编号
                    item_list+=("$cancel_upload_idx" "[取消上传]")

                    # 显示菜单并获取选择（不用额外捕获取消码，选项本身就是“取消上传”）
                    upload_choice=$(dialog --clear \
                                          --title "选择要上传的文件或进入目录（当前目录：${local_dir}）" \
                                          --menu "↑↓选择，Enter确认（文件上传到${CONF_DIR}）:" 18 70 12 \
                                          "${item_list[@]}" \
                                          --stdout)

                    # 1. 用户按ESC（upload_choice为空）：直接退出
                    if [ -z "${upload_choice}" ]; then
                        break
                    fi
                    # 2. 选择“取消上传”：退出循环
                    if [ "${upload_choice}" -eq "${cancel_upload_idx}" ]; then
                        break
                    fi
                    # 3. 选择“返回上级目录”：更新目录并继续循环
                    if [ "${upload_choice}" -eq "${back_to_parent_idx}" ]; then
                        if [ "${local_dir}" = "/" ]; then
                            dialog --title "提示" --msgbox "已在根目录，无法返回上级！" 6 45
                            continue
                        fi
                        local_dir=$(dirname "${local_dir}")
                        continue
                    fi
                    # 4. 选择文件/目录：解析并处理
                    local selected_idx=$((upload_choice - 1))
                    local selected_item="${item_list[$((selected_idx * 2 + 1))]}"
                    local item_type=$(echo "${selected_item}" | cut -d' ' -f1)
                    local item_name=$(echo "${selected_item}" | cut -d' ' -f2-)
                    if [ "${item_type}" = "目录:" ]; then
                        local_dir="${local_dir}/${item_name}"
                        continue
                    elif [ "${item_type}" = "文件:" ]; then
                        local local_file="${local_dir}/${item_name}"
                        local dest_file="${CONF_DIR}/${item_name}"
                        cp -f "${local_file}" "${dest_file}"
                        chmod 644 "${dest_file}"
                        dialog --title "上传成功" --msgbox "文件上传完成！\n本地：${local_file}\n目标：${dest_file}" 7 65
                        break
                    fi
                done
                ;;

            "0")
                break
                ;;
            *)
                dialog --title "错误" --msgbox "无效选择，请重试！" 6 40
                ;;
        esac
    done
}

is_within_home() {
    local target_dir="$1"
    local home_abs=$(realpath "${USER_HOME}")
    local target_abs=$(realpath "${target_dir}")
    [[ "${target_abs}" == "${home_abs}"* ]]
}

handle_image_build() {
    local selection=""
    local current_dir="${USER_HOME}"

    while true; do
        local item_list=()
        local counter=1
        if ! is_within_home "${current_dir}"; then
            dialog --title "访问限制" --msgbox "已超出家目录访问范围，自动返回家目录！" 6 50
            current_dir="${USER_HOME}"
            continue
        fi
        for item in "${current_dir}"/*; do
            [ ! -e "${item}" ] && continue
            if [ -f "${item}" ]; then
                if [ "$(basename "${item}")" = "Dockerfile" ]; then
                    item_list+=("$counter" "文件: $(basename "${item}") 【构建触发文件】")
                else
                    item_list+=("$counter" "文件: $(basename "${item}")")
                fi
            elif [ -d "${item}" ]; then
                item_list+=("$counter" "目录: $(basename "${item}")")
            fi
            ((counter++))
        done
        if [ "${current_dir}" != "${USER_HOME}" ]; then
            item_list+=("$counter" "[返回上级目录]")
            ((counter++))
        fi

        selection=$(dialog --clear \
                          --title "镜像构建（仅允许访问家目录：${USER_HOME}）" \
                          --menu "↑↓浏览目录，选中 Dockerfile 按 Enter 构建；按 ESC 返回子菜单" 18 70 12 \
                          "${item_list[@]}" \
                          --stdout)
        local dialog_exit_code=$?

        if [ ${dialog_exit_code} -ne 0 ]; then
            return 0
        fi

        if [ "${current_dir}" != "${USER_HOME}" ] && [ "${selection}" -eq $((counter - 1)) ]; then
            local parent_dir=$(dirname "${current_dir}")
            if is_within_home "${parent_dir}"; then
                current_dir="${parent_dir}"
            else
                dialog --title "访问限制" --msgbox "不允许访问家目录之外的目录！" 6 45
            fi
            continue
        fi

        local selected_idx=$((selection - 1))
        local selected_item="${item_list[$((selected_idx * 2 + 1))]}"
        local item_type=$(echo "${selected_item}" | cut -d' ' -f1)
        local item_name=$(echo "${selected_item}" | cut -d' ' -f2 | sed 's/【.*】//')  # 去掉 Dockerfile 标记
        local full_path="${current_dir}/${item_name}"

        if [ "${item_type}" = "目录:" ]; then
            if is_within_home "${full_path}"; then
                current_dir="${full_path}"
            else
                dialog --title "访问限制" --msgbox "不允许访问家目录之外的目录！" 6 45
            fi
        elif [ "${item_type}" = "文件:" ]; then
            if [ "${item_name}" = "Dockerfile" ]; then
                "${BUILD_SCRIPT}" "${full_path}"
                return 0
            else
                dialog --title "提示" --msgbox "选中的是普通文件（${item_name}），请选择 Dockerfile 文件触发构建！" 6 60
            fi
        fi
    done
}

show_custom_deploy_submenu() {
    local temp_sub=$(mktemp -t dialog.XXXXXX)
    trap "rm -f ${temp_sub}" EXIT

    while true; do
        dialog --clear --title "自定义部署子菜单" \
            --menu "日志存储：${WORKSPACE} | 配置存储：${CONF_DIR}" ${MENU_HEIGHT} ${WINDOW_WIDTH} 5 \
            "1" "镜像拉取 - 常用镜像推荐+华为云SWR" \
            "2" "配置编写 - 编辑/上传配置文件（列表选择）" \
            "3" "模板修改 - 复制模板文件到配置目录" \
            "4" "镜像构建 - 选择 Dockerfile 触发构建" \
            "0" "返回主菜单" 2>"${temp_sub}"
        
        local exit_code=$?
        if [ ${exit_code} -ne 0 ]; then
            break
        fi

        local sub_choice=$(cat "${temp_sub}")
        case "${sub_choice}" in
            "1") handle_image_pull ;;
            "2") handle_config_edit_upload ;;
            # 在这里调用独立的模板修改脚本
            "3") "${CURRENT_DIR}/template_modify.sh" ;;
            "4") handle_image_build ;;
            "0") break ;;
            *) dialog --title "错误" --msgbox "无效选择！" ${MENU_HEIGHT} ${WINDOW_WIDTH} ;;
        esac
    done
}

main() {
    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    show_custom_deploy_submenu
}

main
