#!/bin/sh

# ========================================================
# 模板修改功能脚本
# 功能：将 /opt/app/templates 下的文件复制到 /opt/app/conf
# ========================================================

# 配置目录
CONF_DIR="/opt/app/conf"
# 模板目录
TEMPLATES_DIR="/opt/app/templates"
# 交互窗口大小
WINDOW_WIDTH=85
WINDOW_HEIGHT=15

# ------------------------------
# 函数：检查并创建目录
# ------------------------------
check_and_create_dir() {
    local dir_path="$1"
    if [ ! -d "${dir_path}" ]; then
        mkdir -p "${dir_path}"
        chmod 755 "${dir_path}"
    fi
}

# ------------------------------
# 主逻辑开始
# ------------------------------

# 确保模板目录和配置目录存在
check_and_create_dir "${TEMPLATES_DIR}"
check_and_create_dir "${CONF_DIR}"

# 使用一个临时文件来接收 dialog 的输入
temp_file=$(mktemp -t template_modify.XXXXXX)
trap "rm -f ${temp_file}" EXIT # 脚本退出时自动删除临时文件

# 1. 检查模板目录是否为空
if [ -z "$(ls -A "${TEMPLATES_DIR}")" ]; then
    dialog --title "提示" \
           --msgbox "模板目录 ${TEMPLATES_DIR} 为空，没有可复制的模板文件。" \
           8 60
    exit 0
fi

# 2. 构建文件选择菜单（先对文件排序，确保顺序稳定）
files=($(ls -1 "${TEMPLATES_DIR}" | sort))  # 按文件名排序，保证顺序固定
menu_items=()
counter=1
for file in "${files[@]}"; do
    if [ -f "${TEMPLATES_DIR}/${file}" ]; then
        menu_items+=("${counter}" "模板文件: ${file}")
        ((counter++))
    fi
done
menu_items+=("${counter}" "全部复制")

# 3. 显示文件选择菜单
dialog --clear \
       --title "模板修改 - 选择文件" \
       --menu "请选择要复制到 ${CONF_DIR} 的模板文件，或选择“全部复制”。\n按 ESC 键返回。" \
       ${WINDOW_HEIGHT} ${WINDOW_WIDTH} 10 \
       "${menu_items[@]}" \
       2>"${temp_file}"

# 获取用户选择和 dialog 的退出码
exit_code=$?
selection=$(cat "${temp_file}")

# 4. 根据用户选择执行操作
if [ ${exit_code} -ne 0 ]; then
    # 用户按了 ESC 键或关闭了窗口
    exit 0
fi

# 计算“全部复制”选项的索引
all_copy_index=$((counter))

if [ "${selection}" -eq "${all_copy_index}" ]; then
    # 选项：全部复制
    dialog --title "确认操作" \
           --yesno "确定要将模板目录下的所有文件复制到 ${CONF_DIR} 吗？\n已存在的文件将被覆盖！" \
           8 60
    if [ $? -ne 0 ]; then
        dialog --title "操作取消" --msgbox "已取消全部复制操作。" 6 40
        exit 0
    fi

    local success_count=0
    for file in "${files[@]}"; do  # 遍历已排序的文件列表
        if [ -f "${TEMPLATES_DIR}/${file}" ]; then
            cp -f "${TEMPLATES_DIR}/${file}" "${CONF_DIR}/${file}"
            chmod 644 "${CONF_DIR}/${file}"
            ((success_count++))
        fi
    done
    dialog --title "操作成功" --msgbox "成功复制了 ${success_count} 个文件到 ${CONF_DIR}。" 8 50

else
    # 选项：复制单个文件
    selected_index=$((selection - 1))  # 转换为数组索引（从0开始）
    selected_file="${files[${selected_index}]}"

    if [ -z "${selected_file}" ]; then
        dialog --title "错误" --msgbox "未找到选中的文件，请重试。" 6 40
        exit 1
    fi

    # 检查目标文件是否存在
    if [ -f "${CONF_DIR}/${selected_file}" ]; then
        dialog --title "文件已存在" \
               --yesno "文件 ${selected_file} 在 ${CONF_DIR} 中已存在。\n是否覆盖？" \
               8 60
        if [ $? -ne 0 ]; then
            dialog --title "操作取消" --msgbox "已取消复制 ${selected_file}。" 6 45
            exit 0
        fi
    fi

    # 执行复制
    cp -f "${TEMPLATES_DIR}/${selected_file}" "${CONF_DIR}/${selected_file}"
    chmod 644 "${CONF_DIR}/${selected_file}"
    dialog --title "操作成功" --msgbox "模板文件 ${selected_file} 已成功复制到 ${CONF_DIR}。" 8 55
fi

exit 0
