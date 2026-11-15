# OpenClaw 免费平台部署镜像
# 基于官方镜像 ghcr.io/openclaw/openclaw，仅追加：
#   - /opt/oc/start.sh  启动时生成配置（模型走 OpenAI 兼容网关）
#   - /opt/oc/gate.js   前置反代，剥掉平台注入的 X-Forwarded-* 头
FROM ghcr.io/openclaw/openclaw:latest

USER root
RUN mkdir -p /opt/oc && chown node:node /opt/oc
COPY --chown=node:node gate.js  /opt/oc/gate.js
COPY --chown=node:node start.sh /opt/oc/start.sh
RUN chmod +x /opt/oc/start.sh

ENV OPENCLAW_HOME=/home/node \
    OPENCLAW_STATE_DIR=/home/node/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json \
    OPENCLAW_WORKSPACE_DIR=/home/node/.openclaw/workspace \
    OPENCLAW_GATEWAY_PORT=18789 \
    NODE_ENV=production

USER node
EXPOSE 7860

# 覆盖官方 ENTRYPOINT，直接跑自己的启动脚本（配置由脚本生成，不需要入口初始化）
ENTRYPOINT ["tini", "-s", "--", "/bin/sh", "/opt/oc/start.sh"]
