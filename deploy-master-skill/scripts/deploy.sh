#!/bin/bash
# 主部署驱动脚本 (本地执行)

set -e

# 加载环境变量
source .deploy-env 2>/dev/null

# 读取用户输入的服务器信息（由 AI 传参或手动输入）
SERVER_HOST=${1}
SERVER_USER=${2}
SSH_KEY=${3:-"$HOME/.ssh/id_rsa"}

if [ -z "$SERVER_HOST" ] || [ -z "$SERVER_USER" ]; then
    echo "用法: ./deploy.sh <服务器IP> <用户名> [SSH密钥路径]"
    exit 1
fi

# 检查变更的服务列表
if [ -z "$CHANGED_SERVICES" ] || [ "$CHANGED_SERVICES" == "[]" ]; then
    echo "无变更服务，退出部署。"
    exit 0
fi

# 清理旧临时文件
rm -f /tmp/*.tar

# 遍历构建
for SERVICE in $CHANGED_SERVICES; do
    echo ">>> 正在构建服务: $SERVICE (平台: linux/amd64)..."
    
    # 获取构建上下文路径
    CONTEXT=$(docker-compose config --service $SERVICE | grep -A 5 "build:" | grep "context:" | head -n 1 | awk '{print $2}' | sed 's/"//g')
    CONTEXT=${CONTEXT:-"."}
    
    # 构建镜像 (自动适配 Linux 架构)
    docker build --platform linux/amd64 -t ${SERVICE}:latest -f ${CONTEXT}/Dockerfile ${CONTEXT}
    
    # 导出为 tar
    echo ">>> 导出镜像: ${SERVICE}.tar"
    docker save ${SERVICE}:latest -o /tmp/${SERVICE}.tar
done

# 传输到服务器
echo ">>> 连接到服务器 ${SERVER_USER}@${SERVER_HOST} 并传输文件..."
scp -i ${SSH_KEY} /tmp/*.tar ${SERVER_USER}@${SERVER_HOST}:/tmp/
scp -i ${SSH_KEY} docker-compose.yml ${SERVER_USER}@${SERVER_HOST}:/app/docker-compose.yml

# 执行远程部署
echo ">>> 远程重启服务..."
ssh -i ${SSH_KEY} ${SERVER_USER}@${SERVER_HOST} << EOF
    cd /app
    for tar_file in /tmp/*.tar; do
        echo "加载镜像: \$tar_file"
        docker load -i \$tar_file
    done
    
    # 重启变更的服务 (利用 CHANGED_SERVICES 环境变量)
    for service in ${CHANGED_SERVICES}; do
        echo "重启服务: \$service"
        docker-compose up -d --no-deps --force-recreate \$service
    done
    
    # 健康检查 (等待 3 秒)
    sleep 3
    docker ps --filter "status=exited" --format "{{.Names}}" | while read name; do
        echo "警告: 容器 \$name 退出！正在回滚..."
        docker-compose logs --tail=20 \$name
        # 这里可添加回滚逻辑，如重新启动旧版本
    done
EOF

# 清理本地临时文件
rm -f /tmp/*.tar
echo ">>> 部署完成！版本: $CURRENT_VERSION"
