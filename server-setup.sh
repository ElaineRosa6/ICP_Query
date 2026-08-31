#!/bin/bash
# 腾讯云服务器端快速安装脚本
# 使用方法：ssh root@服务器IP "bash -s" < server-setup.sh

set -e

echo "====================================="
echo "  ICP_Query 服务器环境初始化"
echo "====================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[成功]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[警告]${NC} $1"; }

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    log_warn "请以 root 用户运行此脚本"
    exit 1
fi

# 安装 Docker
install_docker() {
    log_info "检查 Docker 是否已安装..."

    if command -v docker &> /dev/null; then
        log_success "Docker 已安装：$(docker --version)"
        return 0
    fi

    log_info "正在安装 Docker..."

    # 检测操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        log_warn "无法检测操作系统类型，尝试通用安装..."
        curl -fsSL https://get.docker.com | bash -s docker
        return 0
    fi

    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y ca-certificates curl gnupg lsb-release
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        centos|rhel|almalinux|rocky|fedora)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        *)
            log_warn "不支持的操作系统：$OS，尝试通用安装..."
            curl -fsSL https://get.docker.com | bash -s docker
            ;;
    esac

    systemctl start docker
    systemctl enable docker

    log_success "Docker 安装完成：$(docker --version)"
}

# 安装 Docker Compose（如果插件不可用）
install_docker_compose() {
    log_info "检查 Docker Compose..."

    if docker compose version &> /dev/null; then
        log_success "Docker Compose 已安装：$(docker compose version)"
        return 0
    fi

    if command -v docker-compose &> /dev/null; then
        log_success "docker-compose 已安装：$(docker-compose --version)"
        return 0
    fi

    log_info "正在安装 Docker Compose..."

    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d '"' -f 4)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    log_success "Docker Compose 安装完成：$(docker-compose --version)"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."

    # 检查 firewalld
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=16181/tcp
        firewall-cmd --reload
        log_success "firewalld 已配置，端口 16181 已开放"
    # 检查 ufw
    elif command -v ufw &> /dev/null; then
        ufw allow 16181/tcp
        log_success "ufw 已配置，端口 16181 已开放"
    else
        log_warn "未检测到防火墙管理工具，请手动开放端口 16181"
        log_info "如果使用 firewalld：firewall-cmd --permanent --add-port=16181/tcp && firewall-cmd --reload"
        log_info "如果使用 ufw：ufw allow 16181/tcp"
    fi
}

# 部署应用
deploy_app() {
    log_info "部署 ICP_Query 应用..."

    # 停止旧容器
    if docker ps -a --format '{{.Names}}' | grep -q '^ymicp$'; then
        log_info "停止并删除旧容器..."
        docker stop ymicp 2>/dev/null || true
        docker rm ymicp 2>/dev/null || true
    fi

    # 拉取镜像
    log_info "拉取 Docker 镜像..."
    docker pull yiminger/ymicp:latest

    # 启动容器
    log_info "启动容器..."
    docker run -d \
        --name ymicp \
        -p 16181:16181 \
        --restart unless-stopped \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        yiminger/ymicp:latest

    log_success "应用部署完成"
}

# 验证部署
verify() {
    log_info "正在验证部署..."

    sleep 5

    # 检查容器状态
    STATUS=$(docker inspect -f '{{.State.Status}}' ymicp 2>/dev/null || echo "not_found")

    if [ "$STATUS" = "running" ]; then
        log_success "容器运行正常"

        # 检查端口
        if ss -tuln | grep -q ':16181'; then
            log_success "端口 16181 正在监听"
        else
            log_warn "端口 16181 未监听，请稍后重试"
        fi

        # 获取服务器 IP
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  部署成功！${NC}"
        echo -e "${GREEN}  访问地址：http://${SERVER_IP}:16181${NC}"
        echo -e "${GREEN}  容器名称：ymicp${NC}"
        echo -e "${GREEN}  查看日志：docker logs -f ymicp${NC}"
        echo -e "${GREEN}  重启容器：docker restart ymicp${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        log_error "容器状态异常：$STATUS"
        log_info "查看日志：docker logs ymicp"
        docker logs ymicp --tail 50
        exit 1
    fi
}

# 创建管理脚本
create_management_script() {
    log_info "创建管理脚本..."

    cat > /usr/local/bin/ymicp.sh << 'SCRIPT'
#!/bin/bash
# ymicp 容器管理脚本

case "$1" in
    status)
        docker ps -a --filter name=ymicp
        docker stats ymicp --no-stream
        ;;
    logs)
        docker logs -f --tail ${2:-100} ymicp
        ;;
    restart)
        docker restart ymicp
        ;;
    stop)
        docker stop ymicp
        ;;
    start)
        docker start ymicp
        ;;
    update)
        docker pull yiminger/ymicp:latest
        docker stop ymicp && docker rm ymicp
        docker run -d --name ymicp -p 16181:16181 --restart unless-stopped yiminger/ymicp:latest
        ;;
    *)
        echo "用法：ymicp.sh {status|logs|restart|stop|start|update}"
        echo ""
        echo "命令："
        echo "  status     查看容器状态和资源使用"
        echo "  logs [N]   查看最近 N 行日志（默认 100）"
        echo "  restart    重启容器"
        echo "  stop       停止容器"
        echo "  start      启动容器"
        echo "  update     更新到最新版本"
        ;;
esac
SCRIPT

    chmod +x /usr/local/bin/ymicp.sh
    log_success "管理脚本已创建：ymicp.sh"
}

# 主流程
main() {
    install_docker
    install_docker_compose
    configure_firewall
    deploy_app
    verify
    create_management_script

    echo ""
    echo "提示："
    echo "  - 请使用 'ymicp.sh' 命令管理容器"
    echo "  - 查看日志：ymicp.sh logs"
    echo "  - 查看状态：ymicp.sh status"
    echo "  - 更新版本：ymicp.sh update"
    echo ""
}

main "$@"
