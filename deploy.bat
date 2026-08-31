@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM ============================================
REM ICP_Query Windows 部署脚本
REM 适用于 Windows CMD/PowerShell
REM ============================================

echo.
echo ╔══════════════════════════════════════════════════════════╗
echo ║           ICP_Query 腾讯云服务器部署工具                  ║
echo ╚══════════════════════════════════════════════════════════╝
echo.

REM 加载配置（从 deploy-config.sh 读取，这里简化为直接设置）
set SERVER_IP=
set SSH_USER=root
set SSH_PORT=22
set CONTAINER_NAME=ymicp
set HOST_PORT=16181

REM 检查参数
if "%1"=="help" goto :help
if "%1"=="-h" goto :help
if "%1"=="--help" goto :help

:check_config
if "%SERVER_IP%"=="" (
    echo [错误] 请先设置服务器 IP 地址
    echo.
    set /p SERVER_IP=请输入腾讯云服务器 IP 地址：
    if "!SERVER_IP!"=="" (
        echo [错误] IP 地址不能为空
        pause
        exit /b 1
    )
    echo.
    echo 提示：可以将 IP 写入此脚本避免每次输入
    echo 在脚本开头修改 set SERVER_IP=你的IP
    echo.
)

:menu
echo 请选择操作：
echo 1. 安装 Docker 并部署应用
echo 2. 手动 Docker 部署
echo 3. 查看容器状态
echo 4. 查看容器日志
echo 5. 重启容器
echo 6. 更新到最新版本
echo 7. 退出
echo.
set /p choice=请输入选项 (1-7)：

if "%choice%"=="1" goto :deploy
if "%choice%"=="2" goto :manual_deploy
if "%choice%"=="3" goto :status
if "%choice%"=="4" goto :logs
if "%choice%"=="5" goto :restart
if "%choice%"=="6" goto :update
if "%choice%"=="7" goto :end
echo.
echo [错误] 无效选项，请重新选择
echo.
goto :menu

:deploy
echo.
echo [信息] 正在连接到服务器 %SERVER_IP%...
echo [信息] 此操作将：
echo   1. 在服务器上安装 Docker
echo   2. 拉取 ICP_Query 镜像
echo   3. 启动容器
echo.
echo 请确保：
echo   - 服务器安全组已开放端口 %HOST_PORT%
echo   - 你已配置 SSH 免密登录或准备好密码
echo.
pause

ssh -o StrictHostKeyChecking=no -p %SSH_PORT% %SSH_USER%@%SERVER_IP% "curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun && systemctl start docker && systemctl enable docker && docker pull yiminger/ymicp:latest && docker run -d --name ymicp -p %HOST_PORT%:16181 --restart unless-stopped yiminger/ymicp:latest"

echo.
echo [信息] 部署完成，正在验证服务...
timeout /t 5 /nobreak >nul

curl -s -o nul -w "HTTP 状态码：%%{http_code}\n" http://%SERVER_IP%:%HOST_PORT%
echo.
echo [成功] 部署完成！访问地址：http://%SERVER_IP%:%HOST_PORT%
pause
goto :menu

:manual_deploy
echo.
echo [信息] 正在连接到服务器...
echo.
echo 请依次执行以下命令：
echo.
echo 1. 安装 Docker：
echo    curl -fsSL https://get.docker.com ^| bash -s docker --mirror Aliyun
echo.
echo 2. 启动 Docker：
echo    systemctl start docker
echo    systemctl enable docker
echo.
echo 3. 拉取镜像：
echo    docker pull yiminger/ymicp:latest
echo.
echo 4. 启动容器：
echo    docker run -d --name ymicp -p %HOST_PORT%:16181 --restart unless-stopped yiminger/ymicp:latest
echo.
echo 5. 查看日志：
echo    docker logs -f ymicp
echo.
echo 是否现在 SSH 连接到服务器？(Y/N)
set /p connect=
if /i "!connect!"=="Y" (
    ssh -o StrictHostKeyChecking=no -p %SSH_PORT% %SSH_USER%@%SERVER_IP%
)
goto :menu

:status
echo.
echo [信息] 正在查看容器状态...
ssh -o StrictHostKeyChecking=no -p %SSH_PORT% %SSH_USER%@%SERVER_IP% "docker ps -a --filter name=ymicp --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
echo.
pause
goto :menu

:logs
echo.
echo [信息] 正在查看容器日志...
ssh -o StrictHostKeyChecking=no -p %SSH_PORT% %SSH_USER%@%SERVER_IP% "docker logs ymicp --tail 50"
echo.
pause
goto :menu

:restart
echo.
echo [信息] 正在重启容器...
ssh -o StrictHostKeyChecking=no -p %SSH_PORT% %SSH_USER%@%SERVER_IP% "docker restart ymicp"
echo [成功] 容器已重启
pause
goto :menu

:update
echo.
echo [信息] 正在更新到最新版本...
ssh -o StrictHostKeyChecking=no -p %SSH_PORT% %SSH_USER%@%SERVER_IP% "docker pull yiminger/ymicp:latest && docker stop ymicp && docker rm ymicp && docker run -d --name ymicp -p %HOST_PORT%:16181 --restart unless-stopped yiminger/ymicp:latest"
echo [成功] 更新完成
pause
goto :menu

:help
echo.
echo ICP_Query Windows 部署工具
echo.
echo 用法：双击运行此脚本，或从命令行带参数运行
echo.
echo 交互模式：直接双击 deploy.bat
echo.
echo 功能：
echo   - 一键部署 Docker 应用到腾讯云服务器
echo   - 支持安装 Docker、拉取镜像、启动容器
echo   - 支持查看状态、日志、重启、更新
echo.
echo 注意事项：
echo   - 需要安装 OpenSSH 客户端（Windows 10+ 已内置）
echo   - 建议配置 SSH 免密登录
echo   - 确保服务器安全组已开放端口 %HOST_PORT%
echo.
pause
goto :end

:end
echo.
echo 感谢使用 ICP_Query 部署工具！
echo.
pause
