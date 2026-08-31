#!/bin/bash
# ICP_Query 部署配置文件
# 请根据实际情况修改以下配置

# 腾讯云服务器配置
SERVER_IP="132.232.231.41"      # 服务器公网 IP 地址（必填）
SSH_USER="root"                 # SSH 登录用户名
SSH_PORT="22"                   # SSH 端口
SSH_KEY="~/.ssh/racknerd_key"  # SSH 密钥路径（留空使用密码登录）
SSH_PASSWORD=""                 # SSH 密码（留空使用密钥登录）

# Docker 容器配置
CONTAINER_NAME="ymicp"          # 容器名称
HOST_PORT="16181"               # 宿主机端口
CONTAINER_PORT="16181"          # 容器端口
DOCKER_IMAGE="yiminger/ymicp"   # Docker 镜像
DOCKER_TAG="latest"             # 镜像标签

# 高级配置
RESTART_POLICY="unless-stopped" # 容器重启策略：no, always, unless-stopped, on-failure
LOG_MAX_SIZE="10m"              # 日志文件最大大小
LOG_MAX_FILE="3"                # 日志文件最大数量
