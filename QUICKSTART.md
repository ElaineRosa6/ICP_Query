# ICP_Query 快速部署指南

## 三分钟部署步骤

### 前提条件

1. 一台腾讯云服务器（CentOS 7+/Ubuntu 20.04+）
2. 已开放安全组端口 `16181`（TCP）
3. 可通过 SSH 访问服务器

### 方法一：一键部署（最简单）

#### Windows 用户

1. 双击运行 `deploy.bat`
2. 按提示输入服务器 IP
3. 选择选项 `1` 安装并部署

#### Linux/Mac 用户（使用 Git Bash）

1. 编辑 `deploy-config.sh`，填入服务器 IP：
   ```bash
   SERVER_IP="你的服务器IP"
   ```

2. 运行部署脚本：
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

### 方法二：服务器端一键安装

SSH 连接到服务器后执行：

```bash
curl -fsSL https://raw.githubusercontent.com/HG-ha/ICP_Query/main/server-setup.sh | bash
```

或手动执行：

```bash
# 1. SSH 连接到服务器
ssh root@你的服务器IP

# 2. 下载并运行安装脚本
wget https://raw.githubusercontent.com/HG-ha/ICP_Query/main/server-setup.sh
chmod +x server-setup.sh
./server-setup.sh
```

### 方法三：手动部署

```bash
# 1. SSH 连接到服务器
ssh root@你的服务器IP

# 2. 安装 Docker
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
systemctl start docker
systemctl enable docker

# 3. 运行容器
docker run -d \
    --name ymicp \
    -p 16181:16181 \
    --restart unless-stopped \
    yiminger/ymicp:latest

# 4. 查看日志
docker logs -f ymicp
```

## 访问服务

部署完成后，在浏览器访问：

```
http://你的服务器IP:16181
```

## 常用管理命令

```bash
# 查看状态
docker ps | grep ymicp

# 查看日志
docker logs -f ymicp

# 重启容器
docker restart ymicp

# 更新版本
docker pull yiminger/ymicp:latest
docker stop ymicp && docker rm ymicp
docker run -d --name ymicp -p 16181:16181 --restart unless-stopped yiminger/ymicp:latest
```

## 注意事项

1. **开放安全组端口**：在腾讯云控制台确保端口 `16181` 已开放
2. **使用密钥登录**：建议配置 SSH 密钥登录而非密码登录
3. **定期更新**：建议定期更新镜像以获取最新功能和修复

## 问题排查

如果无法访问服务：

1. 检查容器状态：`docker ps | grep ymicp`
2. 查看日志：`docker logs ymicp`
3. 检查端口监听：`ss -tuln | grep 16181`
4. 确认腾讯云安全组已开放端口 16181

详细故障排查请参阅 [DEPLOY.md](DEPLOY.md)。
