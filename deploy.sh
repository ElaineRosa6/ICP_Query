#!/bin/bash
# ICP_Query Docker 部署脚本
# 适用于腾讯云服务器一键部署

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/deploy-config.sh"

# 检查配置
if [ -z "$SERVER_IP" ]; then
    echo -e "${RED}错误：请在 deploy-config.sh 中设置 SERVER_IP${NC}"
    exit 1
fi

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# SSH 执行命令
ssh_exec() {
    SSH_OPTS="-o StrictHostKeyChecking=no -p ${SSH_PORT}"
    if [ -n "$SSH_KEY" ] && [ -f "${SSH_KEY/#\~/$HOME}" ]; then
        SSH_OPTS="$SSH_OPTS -i ${SSH_KEY/#\~/$HOME}"
    fi

    if [ -n "$SSH_PASSWORD" ]; then
        sshpass -p "$SSH_PASSWORD" ssh $SSH_OPTS "${SSH_USER}@${SERVER_IP}" "$1"
    else
        ssh $SSH_OPTS "${SSH_USER}@${SERVER_IP}" "$1"
    fi
}

# SSH 复制文件
scp_file() {
    SSH_OPTS="-o StrictHostKeyChecking=no -P ${SSH_PORT}"
    if [ -n "$SSH_KEY" ] && [ -f "${SSH_KEY/#\~/$HOME}" ]; then
        SSH_OPTS="$SSH_OPTS -i ${SSH_KEY/#\~/$HOME}"
    fi

    if [ -n "$SSH_PASSWORD" ]; then
        sshpass -p "$SSH_PASSWORD" scp $SSH_OPTS "$1" "${SSH_USER}@${SERVER_IP}:$2"
    else
        scp $SSH_OPTS "$1" "${SSH_USER}@${SERVER_IP}:$2"
    fi
}

# 检查依赖
check_dependencies() {
    if [ -n "$SSH_PASSWORD" ] && ! command -v sshpass &> /dev/null; then
        log_warn "未找到 sshpass，将使用密钥登录方式"
        SSH_PASSWORD=""
    fi
}

# 安装 Docker
install_docker() {
    log_info "正在安装 Docker..."

    ssh_exec "
        # 检查 Docker 是否已安装
        if command -v docker &> /dev/null; then
            echo 'Docker 已安装'
            docker --version
            exit 0
        fi

        # 安装 Docker
        curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun

        # 启动 Docker 服务
        systemctl start docker
        systemctl enable docker

        echo 'Docker 安装完成'
        docker --version
    "

    log_success "Docker 安装成功"
}

# 部署应用
deploy() {
    log_info "开始部署 ICP_Query..."

    # 1. 停止并删除旧容器
    log_info "检查是否存在旧容器..."
    ssh_exec "
        if docker ps -a --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}$'; then
            echo '停止旧容器...'
            docker stop ${CONTAINER_NAME} || true
            echo '删除旧容器...'
            docker rm ${CONTAINER_NAME} || true
            echo '旧容器已清理'
        else
            echo '无旧容器'
        fi
    "

    # 2. 拉取最新镜像
    log_info "正在拉取 Docker 镜像 ${DOCKER_IMAGE}:${DOCKER_TAG}..."
    ssh_exec "docker pull ${DOCKER_IMAGE}:${DOCKER_TAG}"
    log_success "镜像拉取完成"

    # 3. 启动容器
    log_info "正在启动容器..."
    ssh_exec "
        docker run -d \
            --name ${CONTAINER_NAME} \
            -p ${HOST_PORT}:${CONTAINER_PORT} \
            --restart=${RESTART_POLICY} \
            --log-opt max-size=${LOG_MAX_SIZE} \
            --log-opt max-file=${LOG_MAX_FILE} \
            ${DOCKER_IMAGE}:${DOCKER_TAG}
    "

    log_success "容器启动成功"
}

# 验证部署
verify() {
    log_info "正在验证部署..."

    sleep 5

    # 检查容器状态
    CONTAINER_STATUS=$(ssh_exec "docker inspect -f '{{.State.Status}}' ${CONTAINER_NAME} 2>/dev/null || echo 'not_found'")

    if [ "$CONTAINER_STATUS" = "running" ]; then
        log_success "容器运行正常"

        # 检查端口监听
        log_info "检查端口监听..."
        ssh_exec "
            if ss -tuln | grep -q ':${HOST_PORT}'; then
                echo '端口 ${HOST_PORT} 正在监听'
            else
                echo '端口 ${HOST_PORT} 未监听'
            fi
        "

        # 测试服务可访问性
        log_info "测试服务响应..."
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${SERVER_IP}:${HOST_PORT}" 2>/dev/null || echo "000")

        if [ "$HTTP_STATUS" = "200" ]; then
            log_success "服务可正常访问！"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}  部署成功！${NC}"
            echo -e "${GREEN}  访问地址：http://${SERVER_IP}:${HOST_PORT}${NC}"
            echo -e "${GREEN}  容器名称：${CONTAINER_NAME}${NC}"
            echo -e "${GREEN}  镜像版本：${DOCKER_IMAGE}:${DOCKER_TAG}${NC}"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        else
            log_warn "服务 HTTP 状态码：${HTTP_STATUS}（可能需要等待几秒才能完全启动）"
            echo -e "${YELLOW}提示：可以使用以下命令查看日志：${NC}"
            echo "  ssh -p ${SSH_PORT} ${SSH_USER}@${SERVER_IP} \"docker logs -f ${CONTAINER_NAME}\""
        fi
    else
        log_error "容器状态异常：${CONTAINER_STATUS}"
        log_info "查看容器日志："
        ssh_exec "docker logs ${CONTAINER_NAME} --tail 50"
        exit 1
    fi
}

# 显示帮助
show_help() {
    echo -e "${BLUE}ICP_Query Docker 部署脚本${NC}"
    echo ""
    echo "用法："
    echo "  ./deploy.sh [命令]"
    echo ""
    echo "命令："
    echo "  deploy      部署或更新应用（默认）"
    echo "  status      查看容器状态"
    echo "  logs        查看容器日志"
    echo "  stop        停止容器"
    echo "  start       启动容器"
    echo "  restart     重启容器"
    echo "  remove      删除容器"
    echo "  update      更新到最新版本"
    echo "  help        显示此帮助信息"
    echo ""
    echo "示例："
    echo "  ./deploy.sh           # 部署应用"
    echo "  ./deploy.sh logs      # 查看日志"
    echo "  ./deploy.sh update    # 更新到最新版本"
}

# 查看状态
show_status() {
    log_info "容器状态："
    ssh_exec "docker ps -a --filter name=${CONTAINER_NAME} --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

    echo ""
    log_info "资源使用："
    ssh_exec "docker stats ${CONTAINER_NAME} --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}'"
}

# 查看日志
show_logs() {
    log_info "容器日志（最近 100 行）："
    ssh_exec "docker logs ${CONTAINER_NAME} --tail 100"
}

# 停止容器
stop_container() {
    log_info "正在停止容器..."
    ssh_exec "docker stop ${CONTAINER_NAME}"
    log_success "容器已停止"
}

# 启动容器
start_container() {
    log_info "正在启动容器..."
    ssh_exec "docker start ${CONTAINER_NAME}"
    log_success "容器已启动"
}

# 重启容器
restart_container() {
    log_info "正在重启容器..."
    ssh_exec "docker restart ${CONTAINER_NAME}"
    log_success "容器已重启"
}

# 删除容器
remove_container() {
    log_warn "确定要删除容器吗？此操作不可逆！"
    read -p "输入 yes 确认删除： " confirm
    if [ "$confirm" = "yes" ]; then
        log_info "正在停止并删除容器..."
        ssh_exec "docker stop ${CONTAINER_NAME} 2>/dev/null; docker rm ${CONTAINER_NAME} 2>/dev/null"
        log_success "容器已删除"
    else
        log_info "操作已取消"
    fi
}

# 更新镜像
update_image() {
    log_info "正在更新到最新版本..."

    # 拉取最新镜像
    ssh_exec "docker pull ${DOCKER_IMAGE}:latest"

    # 停止并删除旧容器
    ssh_exec "docker stop ${CONTAINER_NAME} 2>/dev/null; docker rm ${CONTAINER_NAME} 2>/dev/null"

    # 启动新容器
    ssh_exec "
        docker run -d \
            --name ${CONTAINER_NAME} \
            -p ${HOST_PORT}:${CONTAINER_PORT} \
            --restart=${RESTART_POLICY} \
            --log-opt max-size=${LOG_MAX_SIZE} \
            --log-opt max-file=${LOG_MAX_FILE} \
            ${DOCKER_IMAGE}:latest
    "

    log_success "更新完成"

    # 验证
    verify
}

# 主函数
main() {
    check_dependencies

    case "${1:-deploy}" in
        deploy)
            install_docker
            deploy
            verify
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        stop)
            stop_container
            ;;
        start)
            start_container
            ;;
        restart)
            restart_container
            ;;
        remove)
            remove_container
            ;;
        update)
            update_image
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令：$1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
