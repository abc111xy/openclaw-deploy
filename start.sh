#!/bin/sh
# OpenClaw 容器启动脚本（Render / Koyeb / Zeabur / Fly 通用）
# 职责：生成 openclaw.json -> 起前置网关（剥平台转发头）-> 启动 gateway
set -eu

: "${OPENCLAW_HOME:=/home/node}"
: "${OPENCLAW_STATE_DIR:=$OPENCLAW_HOME/.openclaw}"
: "${OPENCLAW_CONFIG_PATH:=$OPENCLAW_STATE_DIR/openclaw.json}"
: "${OPENCLAW_WORKSPACE_DIR:=$OPENCLAW_STATE_DIR/workspace}"
: "${OPENCLAW_GATEWAY_PORT:=18789}"
: "${MODEL:=kilo-auto/free}"
: "${OPENAI_API_BASE:=https://free-gw.pages.dev/v1}"
: "${OPENAI_API_KEY:=sk-free-gw-anykey}"
: "${OPENCLAW_GATEWAY_TOKEN:=}"

mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE_DIR" "$OPENCLAW_STATE_DIR/sessions"

# 归一化 base url：去掉结尾斜杠与 /chat/completions
BASE=$(printf '%s' "$OPENAI_API_BASE" | sed 's#/chat/completions$##' | sed 's#/*$##')

if [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
  OPENCLAW_GATEWAY_TOKEN=$(node -e 'console.log(require("crypto").randomBytes(18).toString("hex"))')
  echo "[boot] no gateway token provided, generated one (printed below)"
  echo "[boot] OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN"
fi

cat > "$OPENCLAW_CONFIG_PATH" <<JSON
{
  "models": {
    "providers": {
      "custom": {
        "baseUrl": "$BASE",
        "apiKey": "$OPENAI_API_KEY",
        "api": "openai-completions",
        "models": [
          { "id": "$MODEL", "name": "$MODEL", "contextWindow": 128000 }
        ]
      }
    }
  },
  "agents": { "defaults": { "model": { "primary": "custom/$MODEL" } } },
  "commands": { "restart": true },
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": $OPENCLAW_GATEWAY_PORT,
    "trustedProxies": ["127.0.0.1"],
    "auth": { "mode": "token", "token": "$OPENCLAW_GATEWAY_TOKEN" },
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true,
      "dangerouslyAllowHostHeaderOriginFallback": true
    }
  }
}
JSON
chmod 600 "$OPENCLAW_CONFIG_PATH"

echo "[boot] config written to $OPENCLAW_CONFIG_PATH"
echo "[boot] model=$MODEL base=$BASE gateway=127.0.0.1:$OPENCLAW_GATEWAY_PORT"

# 前置网关：接住平台流量（PORT），剥掉 X-Forwarded-*，转给本机 gateway
node /opt/oc/gate.js &
GATE_PID=$!
echo "[boot] gate pid=$GATE_PID"

# gateway 退出时连带结束网关，避免容器半死
trap 'kill $GATE_PID 2>/dev/null || true' INT TERM EXIT

exec node /app/openclaw.mjs gateway
