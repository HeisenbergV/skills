#!/bin/bash
# 精准检测 docker-compose.yml 中哪些服务的构建上下文发生了变更

set -e

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}>>> 正在扫描代码变更...${NC}"

# 获取当前 Git 最后一次提交的 Hash（用于标记版本）
VERSION=$(git rev-parse --short HEAD)
echo "CURRENT_VERSION=$VERSION" > .deploy-env

# 获取 docker-compose 中定义的所有服务名
SERVICES=$(docker-compose config --services 2>/dev/null)
if [ -z "$SERVICES" ]; then
    echo -e "${RED}错误：未找到 docker-compose.yml 或服务列表为空${NC}"
    exit 1
fi

# 获取变更的文件列表（对比 HEAD 与上一个 Commit，可自行替换为 origin/main）
CHANGED_FILES=$(git diff --name-only HEAD^ HEAD 2>/dev/null || git diff --cached --name-only)

if [ -z "$CHANGED_FILES" ]; then
    echo -e "${RED}未检测到任何文件变动 (Git diff 为空)。${NC}"
    echo "CHANGED_SERVICES=[]" >> .deploy-env
    exit 0
fi

# 用于存储需要更新的服务
NEED_UPDATE=()

# 遍历每个服务，检查其构建上下文是否在变更列表中
for SERVICE in $SERVICES; do
    # 获取该服务的构建上下文路径（默认为 .）
    CONTEXT=$(docker-compose config --service $SERVICE 2>/dev/null | grep -A 5 "build:" | grep "context:" | head -n 1 | awk '{print $2}')
    
    # 如果服务没有 build 字段（使用 image 直接拉取），跳过
    if [ -z "$CONTEXT" ]; then
        continue
    fi

    # 移除可能的引号和斜杠
    CONTEXT=$(echo $CONTEXT | sed 's/"//g' | sed 's/'\''//g')
    
    # 检查变更文件是否位于该上下文路径下
    for FILE in $CHANGED_FILES; do
        # 如果文件路径以 CONTEXT 开头（或者在根目录且 CONTEXT 为 .）
        if [[ "$FILE" == "$CONTEXT"* ]] || [[ "$CONTEXT" == "." && "$FILE" != "docker-compose.yml" ]]; then
            NEED_UPDATE+=("$SERVICE")
            break
        fi
    done

    # 额外检测：如果 docker-compose.yml 本身变了，强制更新所有服务
    if echo "$CHANGED_FILES" | grep -q "docker-compose.yml"; then
        NEED_UPDATE+=("$SERVICE")
    fi
done

# 去重
if [ ${#NEED_UPDATE[@]} -gt 0 ]; then
    UNIQUE_SERVICES=($(printf "%s\n" "${NEED_UPDATE[@]}" | sort -u))
    echo -e "${GREEN}>>> 检测到需要更新的服务: ${UNIQUE_SERVICES[*]}${NC}"
    echo "CHANGED_SERVICES=(${UNIQUE_SERVICES[*]})" >> .deploy-env
else
    echo -e "${RED}没有需要更新的服务 (相关代码未变动)。${NC}"
    echo "CHANGED_SERVICES=[]" >> .deploy-env
    exit 0
fi
