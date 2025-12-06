#!/bin/sh

# ==============================================================================
# 脚本名称: image_pull.sh
# 功能描述: Docker镜像拉取逻辑封装（无交互、日志纯净），支持：
#            1. 接收镜像名+标签，验证标签有效性并拉取；
#            2. 接收镜像名（无标签），返回推荐标签列表；
#            3. 标签验证失败时，返回推荐标签列表。
# 调用方式:
#   - 拉取指定标签：./image_pull.sh <镜像名> <标签>
#   - 获取推荐标签：./image_pull.sh <镜像名>
# 输出格式:
#   - 拉取进度：实时输出 `docker pull` 过程（stdout）；
#   - 推荐标签：每行格式为 "序号 标签 说明"（stdout）；
#   - 错误信息：实时输出错误原因（stderr）；
# 退出码:
#   - 0: 拉取成功 / 推荐标签列表输出成功；
#   - 1: 参数错误；
#   - 2: Docker服务未运行；
#   - 3: 标签验证失败（已输出推荐标签）；
#   - 4: 拉取/打标失败；
#   - 5: 推荐标签获取失败。
# ==============================================================================

# -------------------------- 全局配置 --------------------------
MIRROR_API="https://docker.aityp.com/api/v1/image?search="
MAX_RECOMMEND=5

# -------------------------- 工具函数 --------------------------
# 检查Docker服务状态
check_docker_status() {
    if ! systemctl is-active --quiet docker; then
        echo "错误：Docker服务未运行！请先启动Docker（systemctl start docker）" >&2
        exit 2
    fi
}

# -------------------------- 核心逻辑函数 --------------------------
# 1. 标签有效性验证
check_tag_exists() {
    local image_name=$1
    local tag=$2

    # 调用API验证标签
    local api_response=$(curl -s --connect-timeout 10 --max-time 10 "${MIRROR_API}${image_name}:${tag}")

    # 检查API响应是否为有效JSON
    if ! echo "${api_response}" | jq . >/dev/null 2>&1; then
        echo "错误：镜像站API返回无效JSON，请检查网络或API地址" >&2
        exit 5
    fi

    # 提取mirror地址
    local mirror_addr=$(echo "${api_response}" | jq -r '.results[] | select(.source | test("'${image_name}':'${tag}'")) | .mirror' 2>/dev/null | head -n1)

    # 验证结果判断
    if [ -n "${mirror_addr}" ] && [ "${mirror_addr}" != "null" ]; then
        echo "${mirror_addr}"
        return 0
    else
        echo "警告：标签 ${image_name}:${tag} 不存在，为你推荐以下常用标签：" >&2
        return 1
    fi
}

# 2. 获取镜像的所有可用标签
fetch_all_tags_with_mirror() {
    local image_name=$1

    # 调用API获取标签
    local api_response=$(curl -s --connect-timeout 10 --max-time 10 "${MIRROR_API}${image_name}")

    # 检查API响应是否为有效JSON
    if ! echo "${api_response}" | jq . >/dev/null 2>&1; then
        echo "错误：镜像站API返回无效JSON，请检查网络或API地址" >&2
        exit 5
    fi

    # 提取标签+mirror地址（去重、过滤空值）
    local tag_mirror_list=$(echo "${api_response}" | jq -r '.results[] | 
        (.source | split(":")[-1]) as $tag | 
        .mirror as $mirror | 
        select($tag != "" and $mirror != "null") | 
        "\($tag):\($mirror)"' | sort -u)

    # 检查是否获取到标签
    if [ -z "${tag_mirror_list}" ]; then
        echo "错误：未获取到 ${image_name} 的任何标签，可能镜像不存在" >&2
        exit 5
    fi

    echo "${tag_mirror_list}"
}

# 3. 筛选常用标签
filter_useful_tags() {
    local tag_mirror_list=$1
    local filtered=()

    # 优先保留常用标签（latest、stable、alpine、主版本号）
    for tag_mirror in ${tag_mirror_list}; do
        tag=$(echo "${tag_mirror}" | cut -d':' -f1)
        if [[ $tag =~ ^latest$ || $tag =~ ^stable || $tag =~ -alpine$ || $tag =~ ^[0-9]+\.[0-9]+$ || $tag =~ ^[0-9]+\.[0-9]+-alpine$ ]]; then
            filtered+=("${tag_mirror}")
        fi
    done

    # 补充其他标签（确保总数不超过MAX_RECOMMEND）
    if [[ ${#filtered[@]} -lt $MAX_RECOMMEND ]]; then
        for tag_mirror in ${tag_mirror_list}; do
            tag=$(echo "${tag_mirror}" | cut -d':' -f1)
            if [[ ! $tag =~ test && ! $tag =~ beta && ! $tag =~ rc && ! $tag =~ arm && ! " ${filtered[@]} " =~ " ${tag_mirror} " ]]; then
                filtered+=("${tag_mirror}")
                if [[ ${#filtered[@]} -eq $MAX_RECOMMEND ]]; then
                    break
                fi
            fi
        done
    fi

    echo "$(printf '%s\n' "${filtered[@]}" | sort -u)"
}

# 4. 标签按实用性排序
sort_tags_by_usefulness() {
    local filtered_tags=$1
    local sorted=()
    local remaining=()

    # 转换为数组
    while IFS= read -r line; do
        remaining+=("$line")
    done <<< "${filtered_tags}"

    # 按优先级排序：alpine轻量版 > stable稳定版 > 主版本完整版 > latest > 其他
    for priority_pattern in "-alpine$" "^stable" "^[0-9]+\.[0-9]+$" "^latest$"; do
        for item in "${remaining[@]}"; do
            tag=$(echo "${item}" | cut -d':' -f1)
            if [[ $tag =~ $priority_pattern && ! " ${sorted[@]} " =~ " ${item} " ]]; then
                sorted+=("$item")
            fi
        done
    done

    # 补充剩余标签（确保总数不超过MAX_RECOMMEND）
    for item in "${remaining[@]}"; do
        if [[ ! " ${sorted[@]} " =~ " ${item} " ]]; then
            sorted+=("$item")
            if [[ ${#sorted[@]} -eq $MAX_RECOMMEND ]]; then
                break
            fi
        fi
    done

    echo "$(printf '%s\n' "${sorted[@]}")"
}

# 5. 生成标签说明
generate_tag_desc() {
    local tag=$1
    if [[ $tag == "latest" ]]; then
        echo "最新稳定版（快速验证功能）"
    elif [[ $tag =~ -alpine$ ]]; then
        echo "轻量版（体积仅完整版1/40，省资源）"
    elif [[ $tag =~ ^stable ]]; then
        echo "长期维护版（官方长期更新，无兼容风险）"
    elif [[ $tag =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "主版本完整版（包含所有核心模块）"
    else
        echo "热门兼容版（镜像站高频使用）"
    fi
}

# 6. 输出推荐标签列表
output_recommend_tags() {
    local sorted_tags=$1
    local index=1

    # 遍历标签，按格式输出
    while IFS= read -r tag_mirror; do
        tag=$(echo "${tag_mirror}" | cut -d':' -f1)
        desc=$(generate_tag_desc "${tag}")
        echo "${index} ${tag} ${desc}"
        index=$((index+1))
    done <<< "${sorted_tags}"
}

# 7. 拉取镜像（纯净输出，仅保留进度和结果）
pull_image() {
    local mirror_addr=$1
    local image_name=$(echo "${mirror_addr}" | awk -F'[/:]' '{print $(NF-1)}')
    local tag=$(echo "${mirror_addr}" | awk -F':' '{print $NF}')

    # 输出拉取开始信息
    echo "开始拉取镜像：${image_name}:${tag}"
    echo "拉取地址：${mirror_addr}"
    echo "--------------------------------------------------"

    # 执行拉取（实时输出进度，无多余日志）
    docker pull "${mirror_addr}" 2>&1 | tee /dev/stdout
    local pull_exit=$?

    # 拉取失败处理
    if [ ${pull_exit} -ne 0 ]; then
        echo "--------------------------------------------------" >&2
        echo "失败：镜像 ${image_name}:${tag} 拉取失败！" >&2
        exit 4
    fi

    # 拉取成功后打标
    echo "--------------------------------------------------"
    echo "开始打标：${mirror_addr} → ${image_name}:${tag}"
    docker tag "${mirror_addr}" "${image_name}:${tag}" 2>&1 | tee /dev/stdout
    local tag_exit=$?

    # 打标失败处理
    if [ ${tag_exit} -ne 0 ]; then
        echo "警告：镜像拉取成功，但打标失败！" >&2
        exit 4
    fi

    # 最终成功提示
    echo "--------------------------------------------------"
    echo "成功：镜像 ${image_name}:${tag} 拉取并打标完成！"
    exit 0
}

# -------------------------- 主流程 --------------------------
main() {
    # 1. 检查参数（至少1个：镜像名）
    if [ $# -lt 1 ]; then
        echo "错误：参数不足！" >&2
        echo "用法：" >&2
        echo "  拉取指定标签：./image_pull.sh <镜像名> <标签>" >&2
        echo "  获取推荐标签：./image_pull.sh <镜像名>" >&2
        exit 1
    fi

    # 2. 处理参数（镜像名强制小写）
    local image_name=$(echo "$1" | tr 'A-Z' 'a-z')
    local target_tag="$2"

    # 3. 检查Docker服务状态
    check_docker_status

    # 4. 分支逻辑：有标签 → 验证标签；无标签 → 输出推荐标签
    if [ -n "${target_tag}" ]; then
        mirror_addr=$(check_tag_exists "${image_name}" "${target_tag}")
        if [ $? -eq 0 ]; then
            pull_image "${mirror_addr}"
        else
            all_tags=$(fetch_all_tags_with_mirror "${image_name}")
            filtered_tags=$(filter_useful_tags "${all_tags}")
            sorted_tags=$(sort_tags_by_usefulness "${filtered_tags}")
            output_recommend_tags "${sorted_tags}"
            exit 3
        fi
    else
        all_tags=$(fetch_all_tags_with_mirror "${image_name}")
        filtered_tags=$(filter_useful_tags "${all_tags}")
        sorted_tags=$(sort_tags_by_usefulness "${filtered_tags}")
        output_recommend_tags "${sorted_tags}"
        exit 0
    fi
}

main "$@"
