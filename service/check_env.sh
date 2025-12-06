#!/bin/bash
# 脚本名称：env_check.sh（Docker容器化管理工具 - 环境检查脚本）
# 编码格式：UTF-8
# 功能：仅适配 CentOS 系统，校验工具运行所需前置条件
# 输出：结构化检查报告（无特殊符号，清晰易读）

##############################################################################
# 第一部分：全局配置（同步新 config.env 参数，适配多服务）
##############################################################################
# 1. 路径配置（自动获取当前脚本目录）
CURRENT_DIR=$(cd $(dirname $0); pwd)
CONFIG_FILE="${CURRENT_DIR}/config.env"  # 核心配置文件路径（不变）

# 2. 从新 config.env 读取的变量（替换旧变量，新增多服务/存储参数）
DEPLOY_ROOT=""         # 部署根目录（新参数，替代旧 DEPLOY_DIR）
LOG_ROOT=""            # 日志根目录（新参数，替代旧 LOG_DIR）
COMPOSE_FILE=""        # Docker Compose 配置文件路径（新增）
# 多服务参数（新增，替代旧的 CONTAINER_NAME/IMAGE_NAME/PORT_MAPPING）
SERVICE_NGINX_NAME=""
SERVICE_NGINX_IMAGE=""
SERVICE_NGINX_PORT=""
SERVICE_BACKEND_NAME=""
SERVICE_BACKEND_IMAGE=""
SERVICE_BACKEND_PORT=""
SERVICE_MYSQL_NAME=""
SERVICE_MYSQL_IMAGE=""
SERVICE_MYSQL_PORT=""
# Docker 存储配置（新增，从 config.env 读取，替代硬编码）
DOCKER_STORAGE_DIR=""
MIN_DOCKER_SPACE=""
MIN_DEPLOY_SPACE=""

# 3. 保留不变的配置（阈值仅作默认兜底，实际优先用 config.env 的值）
MIN_DOCKER_VERSION="20.10"  # Docker最低支持版本
SUPPORTED_CENTOS_VER="7"    # 仅支持 CentOS 7+

# 4. 结果存储数组（不变）
PASSED_ITEMS=()   # 通过项
FAILED_ITEMS=()   # 异常项（含解决方案）

##############################################################################
# 第二部分：辅助函数（通用功能抽离，完全未改动）
##############################################################################
# 函数1：打印分隔符（美化输出）
print_separator() {
    echo "=================================================="
}

# 函数2：添加通过项到数组
add_passed() {
    local item="$1"
    PASSED_ITEMS+=("${item}")
}

# 函数3：添加异常项到数组（参数：异常描述 + 解决方案）
add_failed() {
    local desc="$1"
    local solution="$2"
    FAILED_ITEMS+=("【异常描述】：${desc}\n【解决方案】：${solution}")
}

# 函数4：获取CentOS发行版及版本
get_centos_info() {
    if [ -f "/etc/os-release" ]; then
        . /etc/os-release
        # 核心修改：用逗号分隔名称和版本号，避免名称带空格时分割错误
        echo "${NAME},${VERSION_ID}"  # 输出格式："CentOS Linux,7"
    elif [ -f "/etc/redhat-release" ]; then
        # 处理旧系统：/etc/redhat-release 格式为 "CentOS Linux release 7.9.2009 (Core)"
        # 提取名称（前两个字段：CentOS Linux）和版本号（第4个字段：7.9.2009），用逗号分隔
        cat /etc/redhat-release | awk '{name=$1" "$2; version=$4; gsub(/[()//]/,"",version); print name "," version}'
    else
        echo "Unknown,0.0"
    fi
}

# 函数5：获取目录剩余空间（单位：GB，参数：目录路径）
get_free_space() {
    local dir="$1"
    # df -BG：以GB为单位输出，--output=avail：仅取剩余空间列
    free_space=$(df -BG --output=avail "${dir}" | tail -n 1 | tr -d 'G')
    echo "${free_space}"
}

##############################################################################
# 第三部分：核心检查函数（仅修改与新配置相关的模块，其余未动）
##############################################################################
# 检查项1：CentOS系统兼容性（必查，完全未改动）
check_centos_compatibility() {
    local os_info=$(get_centos_info)  # 现在 os_info 格式："CentOS Linux,7" 或 "CentOS Linux,7.9.2009"
    
    # 核心修改：用逗号作为分隔符，提取名称和版本号（忽略名称中的空格）
    IFS=',' read -r OS_NAME OS_VERSION_RAW <<< "${os_info}"  # IFS=, 表示按逗号分割
    
    # 后续过滤和校验逻辑不变（保留之前的修复）
    OS_VERSION=$(echo "${OS_VERSION_RAW}" | tr -cd '0-9.')

    # 校验版本格式（纯数字/数字+小数点）
    if ! [[ "${OS_VERSION}" =~ ^[0-9]+\.?[0-9]*$ ]] || [ -z "${OS_VERSION}" ]; then
        add_failed \
            "CentOS版本提取失败（当前值：${OS_VERSION_RAW}，含非法字符）" \
            "请确认系统为CentOS，且/etc/os-release或/etc/redhat-release文件格式正常"
        return 1
    fi

    # 检查是否为CentOS系统（名称是"CentOS Linux"，包含"CentOS"，判断正常）
    if [[ ! "${OS_NAME}" =~ "CentOS" ]]; then
        add_failed \
            "系统不兼容（当前：${OS_NAME}）" \
            "仅支持CentOS 7+系统，请更换兼容系统后重试"
        return 1
    fi

    # 版本对比（正常执行，OS_VERSION=7 或 7.9.2009）
    if [ "$(echo "${OS_VERSION} >= ${SUPPORTED_CENTOS_VER}" | bc)" -eq 0 ]; then
        add_failed \
            "CentOS版本过低（当前${OS_VERSION}，需≥${SUPPORTED_CENTOS_VER}）" \
            "建议升级系统至CentOS 7+，或更换为兼容版本"
        return 1
    fi

    add_passed "系统兼容性：CentOS ${OS_VERSION} 符合要求（≥${SUPPORTED_CENTOS_VER}）"
    return 0
}

# 检查项2：Docker引擎安装检查（必查，完全未改动）
check_docker_install() {
    # 检查docker命令是否存在
    if ! command -v docker >/dev/null 2>&1; then
        install_cmd="sudo yum install -y yum-utils device-mapper-persistent-data lvm2 && sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo && sudo rpm --import https://mirrors.aliyun.com/docker-ce/linux/centos/gpg && sudo yum --enablerepo=docker-ce-stable clean metadata && sudo yum install -y docker-ce docker-ce-cli containerd.io && sudo systemctl start docker && sudo systemctl enable docker"
        add_failed \
            "Docker引擎未安装" \
            "执行命令安装：${install_cmd}；"
        return 1
    fi
    docker_version_raw=$(docker --version | awk '{print $3}' | tr -d ',')
    # 过滤非法字符：仅保留数字和小数点（避免字母/特殊字符）
    docker_version=$(echo "${docker_version_raw}" | tr -cd '0-9.')
    
    # 校验：确保版本格式合法（x.y 或 x.y.z），且MIN_DOCKER_VERSION已定义
    if ! [[ "${docker_version}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || [ -z "${docker_version}" ] || [ -z "${MIN_DOCKER_VERSION:-}" ]; then
        add_failed \
            "Docker版本解析失败（当前提取值：${docker_version_raw}）" \
            "请确认Docker安装正常，执行docker --version查看输出格式（示例：Docker version 20.10.24, build 8e92328）"
        return 1
    fi

    docker_version_raw=$(docker --version | awk '{print $3}' | tr -d ',')
    # 1. 过滤非法字符：仅保留数字和小数点（彻底剔除字母、空格等）
    docker_version=$(echo "${docker_version_raw}" | tr -cd '0-9.')
    # 2. 校验docker_version：非空 + 格式为 x.y 或 x.y.z
    if [ -z "${docker_version}" ] || ! [[ "${docker_version}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        add_failed \
            "Docker版本提取失败（当前提取值：${docker_version_raw}）" \
            "请先执行 docker --version 查看输出格式，确保第3个字段是版本号（示例：Docker version 20.10.24, build 8e92328）"
        return 1
    fi
    # 3. 校验MIN_DOCKER_VERSION：非空 + 格式合法（避免变量未定义或格式错）
    if [ -z "${MIN_DOCKER_VERSION:-}" ] || ! [[ "${MIN_DOCKER_VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        add_failed \
            "Docker最低版本配置错误（当前值：${MIN_DOCKER_VERSION:-未定义}）" \
            "请在脚本开头全局配置中，正确设置 MIN_DOCKER_VERSION（示例：MIN_DOCKER_VERSION=\"20.10.0\"）"
        return 1
    fi

    # 4. 安全对比：用bc+默认值兜底，确保返回有效整数
    compare_result=$(echo "${docker_version} < ${MIN_DOCKER_VERSION}" | bc 2>/dev/null)
    # 若bc执行失败（如表达式仍有问题），强制设为0
    [ -z "${compare_result}" ] && compare_result=0

    if [ "${compare_result}" -eq 1 ]; then
        add_failed \
            "Docker版本过低（当前${docker_version}，需≥${MIN_DOCKER_VERSION}）" \
            "执行命令升级：sudo yum update docker-ce"
        return 1
    fi
    
    add_passed "Docker版本：${docker_version}（达标）"
    return 0
}

# 检查项3：Docker服务运行状态（必查，完全未改动）
check_docker_service() {
    # CentOS 仅支持 systemctl 管理服务
    if ! command -v systemctl >/dev/null 2>&1; then
        add_failed \
            "系统缺少 systemctl 工具，无法管理 Docker 服务" \
            "请确认系统为 CentOS 7+，并确保 systemctl 正常可用"
        return 1
    fi

    service_status=$(systemctl is-active docker 2>/dev/null)
    if [ "${service_status}" != "active" ]; then
        # 尝试自动启动服务（需root权限）
        if [ "$(id -u)" -eq 0 ]; then
            systemctl start docker >/dev/null 2>&1
            # 再次检查启动结果
            service_status_after=$(systemctl is-active docker 2>/dev/null)
            if [ "${service_status_after}" = "active" ]; then
                add_passed "Docker服务：已自动启动（运行中）"
                return 0
            else
                add_failed \
                    "Docker服务未运行，且自动启动失败" \
                    "手动启动：sudo systemctl start docker；若启动失败，查看日志：journalctl -u docker"
                return 1
            fi
        else
            add_failed \
                "Docker服务未运行（当前用户无权限自动启动）" \
                "1. 切换root用户：su root；2. 启动服务：systemctl start docker；3. 重新执行环境检查"
            return 1
        fi
    fi

    add_passed "Docker服务：运行中"
    return 0
}

# 检查项4：Docker操作权限（必查，完全未改动）
check_docker_permission() {
    # 执行docker info测试权限（无权限会报错）
    if ! docker info >/dev/null 2>&1; then
        add_failed \
            "当前用户无Docker操作权限" \
            "方案1：sudo执行工具（sudo ./deploy_tool.sh）；方案2：添加docker组并重启终端（sudo usermod -aG docker \$USER && newgrp docker）"
        return 1
    fi

    add_passed "操作权限：当前用户拥有Docker操作权限"
    return 0
}

# 检查项5：核心配置文件（config.env）检查（必查，适配新参数）
check_config_file() {
    # 1. 先检查 config.env 文件是否存在（不变）
    if [ ! -f "${CONFIG_FILE}" ]; then
        add_failed \
            "未找到核心配置文件 config.env" \
            "在脚本目录（${CURRENT_DIR}）创建config.env，参考模板补充所有必填参数"
        return 1
    fi

    # 2. 读取新 config.env 的参数（不变）
    source "${CONFIG_FILE}"

    # 3. 定义新的必填参数列表（替换旧的 required_params）
    local required_params=(
        "DEPLOY_ROOT" "LOG_ROOT" "COMPOSE_FILE"
        "SERVICE_NGINX_NAME" "SERVICE_NGINX_IMAGE" "SERVICE_NGINX_PORT"
        "SERVICE_BACKEND_NAME" "SERVICE_BACKEND_IMAGE" "SERVICE_BACKEND_PORT"
        "SERVICE_MYSQL_NAME" "SERVICE_MYSQL_IMAGE" "SERVICE_MYSQL_PORT"
        "DOCKER_STORAGE_DIR" "MIN_DOCKER_SPACE" "MIN_DEPLOY_SPACE"
    )
    local missing_params=()

    # 4. 检查必填参数是否为空（逻辑不变，仅参数列表变）
    for param in "${required_params[@]}"; do
        if [ -z "${!param}" ]; then
            missing_params+=("${param}")
        fi
    done

    if [ ${#missing_params[@]} -ne 0 ]; then
        add_failed \
            "config.env 缺失关键参数：${missing_params[*]}" \
            "在config.env中补充缺失参数，格式参考：\nDEPLOY_ROOT=/opt/app\nSERVICE_NGINX_PORT=80:80\nMIN_DEPLOY_SPACE=10"
        return 1
    fi

    # 5. 保存新参数到全局变量（同步新参数名）
    DEPLOY_ROOT="${DEPLOY_ROOT}"
    LOG_ROOT="${LOG_ROOT}"
    COMPOSE_FILE="${COMPOSE_FILE}"
    SERVICE_NGINX_NAME="${SERVICE_NGINX_NAME}"
    SERVICE_NGINX_IMAGE="${SERVICE_NGINX_IMAGE}"
    SERVICE_NGINX_PORT="${SERVICE_NGINX_PORT}"
    SERVICE_BACKEND_NAME="${SERVICE_BACKEND_NAME}"
    SERVICE_BACKEND_IMAGE="${SERVICE_BACKEND_IMAGE}"
    SERVICE_BACKEND_PORT="${SERVICE_BACKEND_PORT}"
    SERVICE_MYSQL_NAME="${SERVICE_MYSQL_NAME}"
    SERVICE_MYSQL_IMAGE="${SERVICE_MYSQL_IMAGE}"
    SERVICE_MYSQL_PORT="${SERVICE_MYSQL_PORT}"
    DOCKER_STORAGE_DIR="${DOCKER_STORAGE_DIR}"
    MIN_DOCKER_SPACE="${MIN_DOCKER_SPACE}"
    MIN_DEPLOY_SPACE="${MIN_DEPLOY_SPACE}"

    add_passed "配置文件：config.env 存在（关键参数完整）"
    return 0
}

# 检查项6：部署目录与权限（辅助项，适配新目录参数）
check_deploy_dir() {
    # 检查部署根目录（DEPLOY_ROOT）
    if [ ! -d "${DEPLOY_ROOT}" ]; then
        if ! mkdir -p "${DEPLOY_ROOT}" >/dev/null 2>&1; then
            add_failed \
                "部署根目录创建失败（${DEPLOY_ROOT}）" \
                "检查目录权限：sudo chmod 755 $(dirname ${DEPLOY_ROOT})，或更换DEPLOY_ROOT为有权限的路径"
            return 1
        fi
    fi
    # 检查日志根目录（LOG_ROOT）
    if [ ! -d "${LOG_ROOT}" ]; then
        if ! mkdir -p "${LOG_ROOT}" >/dev/null 2>&1; then
            add_failed \
                "日志根目录创建失败（${LOG_ROOT}）" \
                "检查目录权限：sudo chmod 755 $(dirname ${LOG_ROOT})，或更换LOG_ROOT为有权限的路径"
            return 1
        fi
    fi

    # 检查两个目录的读写权限
    if [ ! -w "${DEPLOY_ROOT}" ] || [ ! -r "${DEPLOY_ROOT}" ]; then
        add_failed \
            "部署根目录无读写权限（${DEPLOY_ROOT}）" \
            "执行命令：sudo chmod 755 ${DEPLOY_ROOT}"
        return 1
    fi
    if [ ! -w "${LOG_ROOT}" ] || [ ! -r "${LOG_ROOT}" ]; then
        add_failed \
            "日志根目录无读写权限（${LOG_ROOT}）" \
            "执行命令：sudo chmod 755 ${LOG_ROOT}"
        return 1
    fi

    add_passed "部署目录：${DEPLOY_ROOT}、日志目录：${LOG_ROOT}（均存在且权限正常）"
    return 0
}

# 检查项7：磁盘空间检查（辅助项，适配新阈值参数）
check_disk_space() {
    # 1. 检查部署根目录剩余空间（用新参数 MIN_DEPLOY_SPACE）
    deploy_free=$(get_free_space "${DEPLOY_ROOT}")
    if [ -z "${deploy_free}" ] || [ ${deploy_free} -lt ${MIN_DEPLOY_SPACE} ]; then
        add_failed \
            "部署根目录磁盘空间不足（当前剩余${deploy_free}GB，需≥${MIN_DEPLOY_SPACE}GB）" \
            "1. 清理${DEPLOY_ROOT}所在磁盘的无用文件；\n2. 修改config.env中MIN_DEPLOY_SPACE调整阈值，或更换DEPLOY_ROOT"
        return 1
    fi

    # 2. 检查Docker存储目录（用新参数 DOCKER_STORAGE_DIR 和 MIN_DOCKER_SPACE）
    docker_free=$(get_free_space "${DOCKER_STORAGE_DIR}")
    if [ -z "${docker_free}" ] || [ ${docker_free} -lt ${MIN_DOCKER_SPACE} ]; then
        add_failed \
            "Docker存储目录空间不足（当前剩余${docker_free}GB，需≥${MIN_DOCKER_SPACE}GB）" \
            "清理无用镜像/容器：sudo docker system prune -a（谨慎执行，会删除未使用的镜像和容器）"
        return 1
    fi

    add_passed "磁盘空间：部署目录剩余${deploy_free}GB，Docker存储目录剩余${docker_free}GB（均达标）"
    return 0
}

# 检查项8：依赖工具检查（辅助项，完全未改动）
check_dependency_tools() {
    # 脚本运行所需的系统工具
    local required_tools=("bash" "grep" "awk" "bc" "df" "mkdir" "netstat" "ss" "lsof")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            missing_tools+=("${tool}")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        install_cmd="sudo yum install -y ${missing_tools[*]}"
        add_failed \
            "缺失必要系统工具：${missing_tools[*]}" \
            "执行命令安装：${install_cmd}"
        return 1
    fi

    add_passed "依赖工具（${required_tools[*]}）均已安装"
    return 0
}

# 检查项9：宿主机端口占用检查（辅助项，适配多服务端口 - 一次性汇总所有占用端口）
check_port_occupied() {
    # 定义需要检查的端口映射参数（多服务）
    local port_params=(
        "SERVICE_NGINX_PORT"
        "SERVICE_BACKEND_PORT"
        "SERVICE_MYSQL_PORT"
    )
    local has_error=0  # 标志：是否有端口异常（0=无，1=有）
    local occupied_ports=()  # 存储所有被占用的端口信息

    for port_param in "${port_params[@]}"; do
        # 提取当前服务的端口映射（格式：宿主机端口:容器端口）
        port_mapping="${!port_param}"
        host_port=$(echo "${port_mapping}" | cut -d ':' -f 1)

        # 校验端口格式（必须是数字）
        if ! [[ "${host_port}" =~ ^[0-9]+$ ]]; then
            occupied_ports+=("【参数${port_param}】端口格式错误（值：${port_mapping}），需改为「宿主机端口:容器端口」格式（如 80:80）")
            has_error=1
            continue  # 跳过后续占用检查，继续下一个端口
        fi

        # 检查端口是否占用（逻辑不变）
        if command -v ss >/dev/null 2>&1; then
            port_occupied=$(ss -tuln | grep -c ":${host_port}")
        else
            port_occupied=$(netstat -tuln | grep -c ":${host_port}")
        fi

        if [ ${port_occupied} -ge 1 ]; then
            # 查找占用进程（兼容无lsof的情况）
            if command -v lsof >/dev/null 2>&1; then
                occupy_proc=$(lsof -i :${host_port} | awk 'NR==2 {print $1 "（PID：" $2 "）"}')
                [ -z "${occupy_proc}" ] && occupy_proc="未知进程"
            else
                occupy_proc="未知进程（未安装lsof工具）"
            fi
            # 记录被占用的端口信息
            occupied_ports+=("【端口${host_port}】（对应服务参数：${port_param}）已被${occupy_proc}占用")
            has_error=1
        fi
    done

    # 汇总结果：一次性输出所有异常（若有）
    if [ ${has_error} -eq 1 ]; then
        local error_desc="以下端口存在异常：\n$(IFS=$'\n'; echo "${occupied_ports[*]}")"
        local solution="解决方案：\n1. 停止占用进程：sudo kill -9 对应PID（需替换为实际PID，无PID可先执行 ps aux | grep 进程名 查找）；\n2. 修改端口：在config.env中修改对应服务的PORT参数（如 SERVICE_NGINX_PORT=8082:80）；\n3. 安装lsof工具（可选）：sudo yum install -y lsof，可查看详细占用进程；\n4. 重启环境检查：./check_env.sh"
        add_failed "${error_desc}" "${solution}"
        return 1
    fi

    # 所有端口正常（动态显示实际配置的端口）
    local nginx_port=${SERVICE_NGINX_PORT%%:*}
    local backend_port=${SERVICE_BACKEND_PORT%%:*}
    local mysql_port=${SERVICE_MYSQL_PORT%%:*}
    add_passed "端口状态：Nginx(${nginx_port})、Backend(${backend_port})、MySQL(${mysql_port}) 端口均未被占用"
    return 0
}

# 检查项10：Docker Compose 配置检查（新增，适配多服务）
check_compose_config() {
    # 1. 检查 docker-compose.yml 是否存在
    if [ ! -f "${COMPOSE_FILE}" ]; then
        add_failed \
            "未找到 Docker Compose 配置文件（${COMPOSE_FILE}）" \
            "在指定路径创建 docker-compose.yml，确保包含 nginx、backend、mysql 三个服务的编排配置"
        return 1
    fi

    # 2. 检查 docker-compose.yml 语法是否正确
    if ! docker-compose -f "${COMPOSE_FILE}" config -q >/dev/null 2>&1; then
        add_failed \
            "Docker Compose 配置文件语法错误（${COMPOSE_FILE}）" \
            "执行命令查看具体错误：docker-compose -f ${COMPOSE_FILE} config，修复后重试"
        return 1
    fi

    add_passed "Compose 配置：${COMPOSE_FILE}（文件存在且语法正确）"
    return 0
}

# 第四部分：主逻辑（仅新增 check_compose_config 检查步骤，其余未动）
##############################################################################
main() {
    # 1. 打印脚本说明
    print_separator
    echo "                Docker 环境检查报告（仅适配 CentOS）"
    print_separator
    echo "检查时间：$(date "+%Y-%m-%d %H:%M:%S")"
    echo "脚本目录：${CURRENT_DIR}"
    print_separator
    echo

    # 2. 按优先级执行检查函数（新增 check_compose_config）
    check_dependency_tools        # 必查（依赖工具）
    check_centos_compatibility    # 必查（系统兼容性）
    check_docker_install          # 必查（Docker安装）
    check_docker_service          # 必查（Docker服务状态）
    check_docker_permission       # 必查（操作权限）
    check_config_file             # 必查（配置文件）
    check_compose_config          # 新增必查（Compose配置）
    check_deploy_dir              # 辅助（目录权限）
    check_disk_space              # 辅助（磁盘空间）
    check_port_occupied           # 辅助（端口占用）

    # 3. 输出检查结果（完全未改动）
    echo "【通过项】"
    print_separator
    if [ ${#PASSED_ITEMS[@]} -eq 0 ]; then
        echo "无"
    else
        for ((i=0; i<${#PASSED_ITEMS[@]}; i++)); do
            echo "$((i+1)). ${PASSED_ITEMS[$i]}"
        done
    fi

    echo -e "\n【异常项】"
    print_separator
    if [ ${#FAILED_ITEMS[@]} -eq 0 ]; then
        echo "无（所有检查项通过，可正常使用工具）"
    else
        for ((i=0; i<${#FAILED_ITEMS[@]}; i++)); do
            echo -e "$((i+1)). ${FAILED_ITEMS[$i]}\n"
        done
        echo "提示：请先解决所有异常项，再重新执行环境检查"
    fi

    print_separator
}

##############################################################################
# 脚本入口（调用主逻辑，完全未改动）
##############################################################################
main
