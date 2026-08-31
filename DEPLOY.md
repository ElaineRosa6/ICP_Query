# ICP_Query 腾讯云服务器部署指南

## 目录

- [前置要求](#前置要求)
- [方法一：一键脚本部署（推荐）](#方法一一键脚本部署推荐)
- [方法二：Docker Compose 部署](#方法二docker-compose-部署)
- [方法三：手动 Docker 部署](#方法三手动-docker-部署)
- [常用运维命令](#常用运维命令)
- [故障排查](#故障排查)
- [安全建议](#安全建议)

---

## 前置要求

### 1. 本地环境

- Windows 10/11 系统
- Git Bash 或 WSL（用于运行部署脚本）
- SSH 客户端（Windows 10+ 已内置）

### 2. 服务器环境

- 腾讯云服务器（CentOS 7+/Ubuntu 20.04+/Debian 11+）
- 已开放安全组端口 `16181`（TCP）
- 可通过 SSH 访问服务器

### 3. 开放安全组端口

在腾讯云控制台操作：

1. 进入 [腾讯云控制台](https://console.cloud.tencent.com/)
2. 找到你的云服务器
3. 点击「安全组」→「入站规则」
4. 添加规则：
   - 来源：`0.0.0.0/0`
   - 协议端口：`TCP:16181`
   - 策略：`允许`

---

## 方法一：一键脚本部署（推荐）

### 步骤 1：配置服务器信息

编辑 `deploy-config.sh` 文件，填入你的服务器 IP：

```bash
# 打开配置文件
notepad deploy-config.sh
```

修改以下配置：

```bash
# 必填：服务器公网 IP
SERVER_IP="你的服务器IP"

# 可选：如果使用密钥登录，留空 SSH_PASSWORD
SSH_PASSWORD=""

# 可选：如果使用密码登录，填入密码
# SSH_PASSWORD="你的SSH密码"
```

### 步骤 2：执行部署

在 Git Bash 中运行：

```bash
# 赋予执行权限
chmod +x deploy.sh

# 部署应用
./deploy.sh
```

部署完成后，脚本会显示访问地址。

### 常用命令

```bash
# 查看容器状态
./deploy.sh status

# 查看日志
./deploy.sh logs

# 更新到最新版本
./deploy.sh update

# 重启容器
./deploy.sh restart

# 停止容器
./deploy.sh stop

# 启动容器
./deploy.sh start
```

---

## 方法二：Docker Compose 部署

### 步骤 1：SSH 连接到服务器

```bash
# 使用密钥登录
ssh root@你的服务器IP

# 或使用密码登录
ssh -o StrictHostKeyChecking=no root@你的服务器IP
```

### 步骤 2：安装 Docker

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
systemctl start docker
systemctl enable docker

# CentOS
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
systemctl start docker
systemctl enable docker
```

### 步骤 3：安装 Docker Compose

```bash
# 下载 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 验证安装
docker-compose --version
```

### 步骤 4：上传 docker-compose.yml

在本地 Git Bash 执行：

```bash
# 上传文件到服务器
scp docker-compose.yml root@你的服务器IP:/opt/icp-query/

# 或使用 WinSCP/其他 SFTP 工具上传
```

### 步骤 5：启动服务

```bash
# SSH 到服务器后执行
cd /opt/icp-query
docker-compose up -d

# 查看日志
docker-compose logs -f
```

---

## 方法三：手动 Docker 部署

### 步骤 1：SSH 连接到服务器

```bash
ssh root@你的服务器IP
```

### 步骤 2：安装 Docker

```bash
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
systemctl start docker
systemctl enable docker
docker --version
```

### 步骤 3：拉取镜像并运行

```bash
# 拉取最新镜像
docker pull yiminger/ymicp:latest

# 启动容器
docker run -d \
    --name ymicp \
    -p 16181:16181 \
    --restart unless-stopped \
    --log-opt max-size=10m \
    --log-opt max-file=3 \
    yiminger/ymicp:latest

# 查看容器状态
docker ps

# 查看日志
docker logs -f ymicp
```

### 步骤 4：验证部署

```bash
# 测试服务
curl http://localhost:16181

# 从本地浏览器访问
# http://你的服务器IP:16181
```

---

## 常用运维命令

### 容器管理

```bash
# 查看容器状态
docker ps -a | grep ymicp

# 查看容器资源使用
docker stats ymicp

# 查看容器日志
docker logs ymicp
docker logs -f --tail 100 ymicp

# 重启容器
docker restart ymicp

# 停止容器
docker stop ymicp

# 启动容器
docker start ymicp

# 删除容器
docker stop ymicp && docker rm ymicp
```

### 镜像管理

```bash
# 查看镜像
docker images | grep ymicp

# 更新镜像
docker pull yiminger/ymicp:latest
docker stop ymicp && docker rm ymicp
docker run -d --name ymicp -p 16181:16181 --restart unless-stopped yiminger/ymicp:latest

# 清理旧镜像
docker image prune -f
```

### 进入容器

```bash
# 进入容器 shell
docker exec -it ymicp /bin/bash

# 在容器内执行命令
docker exec ymicp python3 --version
```

### 备份与恢复

```bash
# 备份数据库（如果有持久化数据）
docker cp ymicp:/icpApi/icp_history.db ./backup_$(date +%Y%m%d).db

# 恢复数据
docker cp ./backup_20240101.db ymicp:/icpApi/icp_history.db
docker restart ymicp
```

---

## 故障排查

### 1. 容器无法启动

```bash
# 查看详细日志
docker logs ymicp

# 常见原因：
# - 端口被占用：ss -tuln | grep 16181
# - 镜像拉取失败：docker pull yiminger/ymicp:latest
# - 资源不足：free -m && df -h
```

### 2. 服务无法访问

```bash
# 检查容器是否运行
docker ps | grep ymicp

# 检查端口监听
ss -tuln | grep 16181

# 检查防火墙
# 腾讯云安全组是否开放 16181 端口？
# 服务器防火墙设置：
sudo iptables -L -n | grep 16181

# 测试本地访问
curl http://localhost:16181
```

### 3. 内存占用过高

```bash
# 查看容器资源使用
docker stats ymicp

# 重启容器释放内存
docker restart ymicp

# 限制容器内存（重新运行容器时添加参数）
docker run -d --name ymicp -p 16181:16181 --memory="512m" --restart unless-stopped yiminger/ymicp:latest
```

### 4. 日志文件过大

```bash
# 查看日志大小
docker inspect ymicp | grep -i log

# 清理日志
sudo truncate -s 0 /var/lib/docker/containers/$(docker inspect -f '{{.Id}}' ymicp)/*-json.log

# 或重新运行容器时限制日志大小（已在部署脚本中配置）
```

### 5. 验证码识别失败

```bash
# 查看识别相关日志
docker logs ymicp | grep -i captcha

# 检查模型文件是否存在
docker exec ymicp ls -la /icpApi/model_data/

# 重启服务
docker restart ymicp
```

### 6. 网络连接问题

```bash
# 检查容器网络
docker network ls
docker network inspect bridge

# 测试容器网络
docker exec ymicp ping -c 3 beian.miit.gov.cn

# 如果服务器在中国大陆，确保网络可以访问工信部网站
```

---

## 安全建议

### 1. 使用 SSH 密钥登录

```bash
# 生成密钥（本地执行）
ssh-keygen -t ed25519 -C "your_email@example.com"

# 复制公钥到服务器
ssh-copy-id root@你的服务器IP

# 禁用密码登录（服务器上执行）
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### 2. 配置防火墙

```bash
# Ubuntu/Debian
sudo ufw allow 16181/tcp
sudo ufw enable

# CentOS
sudo firewall-cmd --permanent --add-port=16181/tcp
sudo firewall-cmd --reload
```

### 3. 定期更新镜像

```bash
# 每周更新一次（添加到 crontab）
0 3 * * 0 /opt/scripts/update-ymicp.sh

# update-ymicp.sh 内容：
#!/bin/bash
docker pull yiminger/ymicp:latest
docker stop ymicp && docker rm ymicp
docker run -d --name ymicp -p 16181:16181 --restart unless-stopped yiminger/ymicp:latest
```

### 4. 监控服务状态

```bash
# 使用 systemctl 监控（可选）
sudo tee /etc/systemd/system/ymicp-monitor.service > /dev/null <<EOF
[Unit]
Description=ICP Query Health Monitor
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/docker inspect -f '{{.State.Health.Status}}' ymicp

[Install]
WantedBy=multi-user.target
EOF
```

### 5. 备份重要数据

```bash
# 创建备份脚本
cat > /opt/scripts/backup-ymicp.sh <<EOF
#!/bin/bash
BACKUP_DIR="/opt/backups/ymicp/\$(date +%Y%m%d)"
mkdir -p \$BACKUP_DIR
docker cp ymicp:/icpApi/icp_history.db \$BACKUP_DIR/
find /opt/backups/ymicp/ -mtime +30 -delete  # 保留 30 天
EOF

chmod +x /opt/scripts/backup-ymicp.sh

# 添加到 crontab
0 2 * * * /opt/scripts/backup-ymicp.sh
```

---

## 自定义配置

如果需要自定义配置（如代理、并发数等），可以挂载配置文件：

```bash
# 1. 在服务器上创建配置目录
mkdir -p /opt/icp-query/config

# 2. 上传自定义 config.yml
# 参考项目中的 config.yml 格式

# 3. 运行容器时挂载配置
docker run -d \
    --name ymicp \
    -p 16181:16181 \
    -v /opt/icp-query/config/config.yml:/icpApi/config.yml \
    --restart unless-stopped \
    yiminger/ymicp:latest
```

---

## 技术支持

- 项目仓库：https://github.com/HG-ha/ICP_Query
- 交流群：1029212047（QQ）
- Docker Hub：https://hub.docker.com/r/yiminger/ymicp

---

**注意：** 本项目开源仅用于学习交流逆向与验证码识别技术使用，请遵守相关法律法规。
