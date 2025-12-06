#!/bin/sh

# 镜像构建独立脚本
# 参数: $1 - Dockerfile 文件的绝对路径

if [ -z "$1" ]; then
    echo "错误：未提供 Dockerfile 路径。"
    exit 1
fi

DOCKERFILE="$1"
BUILD_CONTEXT=$(dirname "${DOCKERFILE}")
WINDOW_WIDTH=85
MENU_HEIGHT=15

# 检查 Dockerfile 是否存在且为文件
if [ ! -f "${DOCKERFILE}" ]; then
    dialog --title "错误" --msgbox "Dockerfile 文件 \`${DOCKERFILE}\` 不存在或不是文件！" ${MENU_HEIGHT} ${WINDOW_WIDTH}
    exit 1
fi

# 检查文件名是否为 Dockerfile（严格匹配）
if [ "$(basename "${DOCKERFILE}")" != "Dockerfile" ]; then
    dialog --title "错误" --msgbox "选择的文件不是 Dockerfile！请重新选择。" ${MENU_HEIGHT} ${WINDOW_WIDTH}
    exit 1
fi

# 1. 获取用户输入的镜像标签
temp_file=$(mktemp -t dialog.XXXXXX)
dialog --clear --title "输入镜像标签" --inputbox "请为新镜像输入一个标签（例如：myapp:v1.0）:" ${MENU_HEIGHT} ${WINDOW_WIDTH} "myapp:latest" 2>"${temp_file}"

# 检查用户是否取消输入标签
if [ $? -ne 0 ]; then
    rm -f "${temp_file}"
    dialog --title "提示" --msgbox "镜像标签输入已取消，构建终止。" ${MENU_HEIGHT} ${WINDOW_WIDTH}
    exit 0
fi

IMAGE_TAG=$(cat "${temp_file}")
rm -f "${temp_file}"

# 2. 执行镜像构建并实时显示进度
temp_file=$(mktemp -t build_output.XXXXXX)
dialog --title "构建进度" --msgbox "开始构建镜像 \`${IMAGE_TAG}\`...\n构建上下文：${BUILD_CONTEXT}\nDockerfile：${DOCKERFILE}" ${MENU_HEIGHT} ${WINDOW_WIDTH}

# 执行 docker build（指定 Dockerfile 路径和构建上下文）
dialog --title "构建日志" --tailbox "${temp_file}" ${MENU_HEIGHT} ${WINDOW_WIDTH} &
local tail_pid=$!
docker build -t "${IMAGE_TAG}" -f "${DOCKERFILE}" "${BUILD_CONTEXT}" > "${temp_file}" 2>&1
BUILD_EXIT_CODE=$?

# 等待日志显示进程结束
kill ${tail_pid} >/dev/null 2>&1
wait ${tail_pid} >/dev/null 2>&1

# 3. 显示构建结果
if [ ${BUILD_EXIT_CODE} -eq 0 ]; then
    dialog --title "成功" --msgbox "镜像 \`${IMAGE_TAG}\` 构建完成！\n\n可通过 \`docker images\` 查看。" ${MENU_HEIGHT} ${WINDOW_WIDTH}
else
    dialog --title "失败" --msgbox "镜像构建失败！\n\n详细日志：\n$(cat "${temp_file}")" $((MENU_HEIGHT + 8)) ${WINDOW_WIDTH}
fi

rm -f "${temp_file}"
