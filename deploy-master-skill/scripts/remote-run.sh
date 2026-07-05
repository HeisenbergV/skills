#!/bin/bash
# 服务器端执行脚本 (由 AI 通过 SSH 调用)
# 用法: bash remote-run.sh <服务名1> <服务名2> ...

set -e

DEPLOY_DIR="/app"
cd $DEPLOY_DIR

# 加载所有 tar 包
for tar in /tmp/*.tar; do
    if [ -f "$tar" ]; then
        echo "Loading image from $tar"
        docker load -i "$tar"
        rm -f "$tar" # 加载后删除
    fi
done

# 重启传入的服务
for service in "$@"; do
    echo "Recreating service: $service"
    docker-compose up -d --no-deps --force-recreate "$service"
done

# 清理 dangling 镜像
docker image prune -f

echo "Deployment script finished on server."
