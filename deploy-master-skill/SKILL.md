---
name: docker-universal-deploy
description: 通用增量 Docker 部署工具。支持前后端分离及任意技术栈项目，自动检测变更服务，本地构建镜像并热更新至远程服务器，失败自动回滚。
---

# 通用 Docker 增量部署 Skill

## 触发条件
当用户说“部署到服务器”、“发布更新”、“上线”、“重启服务”或“更新 prod”时激活。

## 前置检查
1. 确保本地已安装 Docker、docker-compose、git、scp/rsync。
2. 确保项目根目录存在 `docker-compose.yml` 文件。
3. **必须优先询问用户**：目标服务器 IP/域名、SSH 用户名、SSH 私钥路径（默认为 `~/.ssh/id_rsa`）。绝对禁止硬编码密码。

## 执行流程（AI 严格按此步骤操作）

### 第一步：增量变更检测（不询问，直接执行）
运行内置脚本检查哪些服务真正发生了变动：
```bash
bash scripts/diff-check.sh
```
该脚本会对比 HEAD 与 HEAD^（或与上次部署 Commit），扫描 docker-compose.yml 中各服务的 build.context 路径。

若没有检测到任何变动，直接告知用户“代码无变动，无需部署”并终止流程。

### 第二步：构建策略选择（询问用户）
拿到变更的服务列表（如 ["backend", "frontend"]），询问用户选择部署模式：

- **模式 1（生产/全量）**：重新构建镜像并上传（适合依赖变更、Dockerfile 变动）。
- **模式 2（开发/热更）**：仅同步变更的代码文件到服务器挂载目录，执行 docker-compose restart（适合只改了几行业务逻辑，速度极快）。

### 第三步：本地构建与打包（模式 1 执行）
遍历变更的服务，执行构建（自动适配 AMD64 架构）：

```bash
docker build --platform linux/amd64 -t <服务名>:latest -f ./<服务路径>/Dockerfile ./<服务路径>
```

导出镜像为 .tar 文件：

```bash
docker save <服务名>:latest -o /tmp/<服务名>.tar
```

### 第四步：连接服务器并传输
使用 scp 传输镜像包（模式 1）或使用 rsync 传输变更代码（模式 2）。

若传输失败（如 SSH 连接中断），提示用户检查网络和防火墙。

### 第五步：远程执行部署（调用 AI 命令）
AI 需要通过 SSH 在远程服务器执行以下逻辑（可由 scripts/remote-run.sh 驱动）：

- 加载镜像：`docker load -i /tmp/<服务>.tar`
- 重启服务：`docker-compose -f /app/docker-compose.yml up -d --no-deps --force-recreate <服务>`
- `--no-deps` 确保只重启该服务，不影响依赖。
- 清理旧镜像：`docker image prune -f`

### 第六步：健康检查与回滚
执行 docker ps 检查容器状态是否为 Up。

如果容器内有健康检查端点（如 http://localhost:8080/health），执行 curl -f 验证。

若 5 秒内容器重启或健康检查失败：

- 执行 `docker-compose logs --tail=50 <服务>` 获取错误日志。
- 自动执行 `docker-compose up -d --no-deps <旧镜像标签>` 回滚。
- 发送失败通知，终止流程。

### 第七步：完成通知
输出部署成功的服务列表、访问地址及当前镜像版本号（Commit ID 或时间戳）。

## 注意事项
- 运行任何 rm -rf、docker system prune -a 等危险命令前必须征求用户同意。
- 所有临时文件（如 /tmp/*.tar）在部署完成后由脚本自动清理。
- 若用户未配置 SSH 免密登录，请在首次运行时引导用户生成密钥。

## 脚本位置
Skill 目录：`/home/zuojx/code/skills/deploy-master-skill/`

执行前 `cd` 到**目标项目根目录**，脚本用绝对路径调用：

- `/home/zuojx/code/skills/deploy-master-skill/scripts/diff-check.sh` — 增量变更检测
- `/home/zuojx/code/skills/deploy-master-skill/scripts/deploy.sh` — 本地构建与上传
- `/home/zuojx/code/skills/deploy-master-skill/scripts/remote-run.sh` — 服务器端加载镜像与重启
