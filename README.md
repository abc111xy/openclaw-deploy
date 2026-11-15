# OpenClaw · 免费容器平台部署包

把 OpenClaw 跑在**免费**托管平台上，得到一个公网地址，控制台直接可用。

## 为什么需要这个包

官方镜像 `ghcr.io/openclaw/openclaw:latest` 不能直接丢上平台，有两个坑：

1. **平台反代头会让 OpenClaw 拒绝服务**
   免费平台（Render / Koyeb / Zeabur / Fly / instabox）都会在请求前加一层反代，注入
   `X-Forwarded-For`、`X-Real-IP`、`X-Forwarded-Proto`。OpenClaw 的 ingress-attribution
   判定看到「非可信代理带来的转发头」，会直接返回 `proxy_attribution_required`，
   控制台白屏、API 401。这就是之前把容器 7860 端口发布到公网后打不开的原因。
   → `gate.js` 在容器内做一层前置反代，**剥掉全部转发头**，让 OpenClaw 看到的是本机直连请求。

2. **镜像没有配置**
   官方镜像的 `openclaw.json` 需要自己提供（模型 provider、gateway token、controlUi 开关）。
   → `start.sh` 在启动时按环境变量生成配置，再拉起 gateway。

## 平台现状（2026-11 实测）

| 平台 | 免费档 | 结论 |
| --- | --- | --- |
| Hugging Face Docker Space | ❌ 需 PRO（402） | 静态免费，运行时收费 |
| Koyeb | ❌ 已取消免费档 | 现 $29/mo 起 |
| **Render** | ✅ Web Service 免费 | 512MB / 15 分钟无流量休眠 / 750 小时/月 / 无持久盘 |
| Zeabur / ClawCloud Run | ✅ 有额度 | 需 GitHub 登录；claw.cloud 在中国大陆常超时 |

## 部署到 Render

1. 把本目录推到 GitHub 公开仓库（或私有仓库 + 授权 Render）。
2. Render Dashboard → **New → Blueprint** → 选中该仓库，会自动读取 `render.yaml`。
   也可以 **New → Web Service → Deploy an existing image** 后用自定义 Dockerfile。
3. 填三个 Secret：
   | 变量 | 说明 |
   | --- | --- |
   | `OPENAI_API_KEY` | 上游模型网关的 key（free-gw 任意值即可） |
   | `OPENAI_API_BASE` | 默认 `https://free-gw.pages.dev/v1` |
   | `MODEL` | 默认 `kilo-auto/free` |
4. 首次构建约 3–6 分钟（要拉 2.3GB 基础镜像）。
5. 部署完成后访问 `https://<service>.onrender.com/`，用 `OPENCLAW_GATEWAY_TOKEN` 登录控制台
   （该值在 Render 的 Environment 页可见，由 `generateValue` 生成）。

## 环境变量

| 变量 | 默认 | 作用 |
| --- | --- | --- |
| `PORT` | 平台注入 | 前置网关监听端口（必须用平台给的值） |
| `OPENCLAW_GATEWAY_PORT` | `18789` | gateway 本机端口，gate 转发目标 |
| `OPENCLAW_GATEWAY_TOKEN` | 随机生成 | 控制台登录 token |
| `OPENAI_API_BASE` | `https://free-gw.pages.dev/v1` | OpenAI 兼容上游 |
| `MODEL` | `kilo-auto/free` | 模型 id |

## 已知限制

- Render 免费实例 **512MB 内存**，OpenClaw 常驻约 300–400MB，跑单会话够用，多开可能 OOM。
- 15 分钟无流量会休眠，下次请求冷启动约 1 分钟；可用外部探针每 10 分钟打一次 `/healthz` 保活。
- 无持久盘：重启后会话历史丢失，配置每次启动重新生成（配置本身无害）。

<!-- rebuild 1794715410 -->
