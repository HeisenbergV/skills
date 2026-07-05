# 部署连接信息（复制为 .env.deploy，勿提交 Git）
# AI 部署时应询问用户，不要硬编码密码

DEPLOY_SERVER_HOST=
DEPLOY_SERVER_USER=root
DEPLOY_SSH_KEY=~/.ssh/id_rsa
DEPLOY_DIR=/app
DEPLOY_MODE=1
# 1=生产/全量镜像  2=开发/热更代码同步
