# 部署：Vercel + Supabase

线上架构：

```
浏览器 ──► Vercel（一个项目，根目录 backend/）
            ├─ web/             Flutter web（FastAPI 挂载，构建时推到 CDN）
            └─ app/main.py      FastAPI（一个 Vercel Function，最长 300 秒）
                   │  Authorization: Bearer <Supabase access token>
                   ▼
           Supabase：Auth（邮箱 + 密码）+ Postgres
```

- **账号**：Flutter 用 `supabase_flutter` 登录，拿到 access token，每个 API 请求都带上；FastAPI 用项目的 JWKS 验证 token（`app/auth.py`）。
- **数据隔离**：每个账号一个 Postgres schema（`u_<用户 id>`），表结构一样。请求的 session 带 `schema_translate_map`，所有 SQL 自动落到这个账号的 schema 里，业务代码不用按用户过滤（`app/db.py`）。账号第一次请求时自动建表。
- **本地开发不变**：`AUTH_MODE` 默认 `dev`，不用登录，SQLite，`./run.sh` 照旧。

---

## 1. Supabase（你来做，约 5 分钟）

1. 在 https://supabase.com 新建项目。**Region 选 Northeast Asia (Seoul)**，和 Vercel 的函数区域 `icn1` 一致，否则每个请求都要跨洋。数据库密码记下来。
2. **Authentication → Sign In / Providers → Email**：保持开启。
   - 开发阶段可以先关掉 **Confirm email**（免得每次注册都要收信；Supabase 自带的发信每小时只有几封）。正式给人用再打开，最好配自己的 SMTP。
3. **Authentication → URL Configuration**：Site URL 填 Vercel 的网址（第 2 步之后才有）；Redirect URLs 加上同一个网址，以及手机 App 用的 `selfinfinity://login-callback`，确认邮件和重置密码的链接才会跳回来。
4. 记下三样东西：
   - **Project URL**：`https://<ref>.supabase.co`（Project Settings → API）
   - **Publishable / anon key**（同一页；**不是** secret / service_role key）
   - **数据库连接串**：右上角 **Connect → Transaction pooler**，端口 6543，形如
     `postgresql://postgres.<ref>:<密码>@aws-0-ap-northeast-2.pooler.supabase.com:6543/postgres`

### Google 登录（可选，约 10 分钟，你来做）

登录卡片里的 “Continue with Google” 走 Supabase 的 Google provider，代码已经接好，只差两边的配置：

1. **Google Cloud Console** → APIs & Services → Credentials → Create credentials → **OAuth client ID**，类型选 **Web application**。
   - 第一次用要先配 **OAuth consent screen**（External，填应用名和你的邮箱即可；测试阶段把自己加进 Test users）。
   - **Authorized redirect URIs** 填：`https://<ref>.supabase.co/auth/v1/callback`
   - 记下 Client ID 和 Client secret。
2. **Supabase** → Authentication → Sign In / Providers → **Google**：打开，填上面的 Client ID 和 Client secret，保存。
3. **Supabase** → Authentication → URL Configuration：Redirect URLs 里要有 Vercel 网址和 `selfinfinity://login-callback`（第 1 节第 3 步已经加过就不用再加）。

用 Google 登录的账号和邮箱账号一样，各自一个 schema，数据互不相通；同一个邮箱先用密码注册、后用 Google 登录，Supabase 会把它们并成一个账号。

## 2. Vercel（你来做）

1. 登录：在项目目录运行 `npx vercel login`（会打开浏览器）。
2. 在 `backend/` 里运行 `npx vercel link`，新建项目（名字随意，例如 `self-infinity`）。
3. 环境变量：在 Vercel 的 Integrations 里连上 Supabase，它会自动加好 `SUPABASE_URL`、`SUPABASE_ANON_KEY`、`POSTGRES_URL` 等。后端直接认这些名字：

   - 数据库：读 `DATABASE_URL`，没有就读集成给的 `POSTGRES_URL`（transaction pooler，端口 6543）。
   - 登录：Vercel 上 `AUTH_MODE` 默认就是 `supabase`，不用设。
   - 网页打包用 `SUPABASE_URL` + `SUPABASE_ANON_KEY`。

   只需要自己再加（勾上 **Production** 和 Preview）：

| 变量 | 值 |
|---|---|
| `OPENAI_API_KEY` | 你的 key（现在线上用的是它，模型默认 `gpt-6-luna`） |
| `LLM_PROVIDER` | 可选：不设就用第一个配了 key 的 provider，一个 key 都没有就是 `mock` |
| `LLM_MODEL` | 可选：换模型时才设 |
| `LLM_TIMEOUT_SECONDS` | 可选：默认 90（推理模型生成一门课约 25 秒） |
| `TAVILY_API_KEY` | 可选，不填用离线搜索替身（没有网上课纲参考） |
| `DEV_EMAILS` | 可选：能看到开发者面板（审计指标）的邮箱，逗号分隔 |
| `TRANSCRIBE_MODEL` / `SPEECH_MODEL` / `SPEECH_VOICE` | 可选：语音转写和朗读（默认 `gpt-transcribe` / `gpt-4o-mini-tts` / `marin`）。语音只走 OpenAI，有 `OPENAI_API_KEY` 就开着；没有就用浏览器自带的识别和朗读 |
| `REALTIME_MODEL` / `LIVE_TRANSCRIBE_MODEL` | 可选：首页 Guide 的实时语音模型、审计的实时转写（默认 `gpt-realtime-2.1` / `gpt-live-transcribe`），走 WebRTC |

   改了环境变量要 **Redeploy** 才生效。

> 注意：网站公开后任何人都能注册，每次审计和生成课程都花你的 DeepSeek 额度。先用 `LLM_PROVIDER=mock` 跑通，或者先别把网址给别人。

## 3. 部署

```bash
SUPABASE_URL=https://<ref>.supabase.co SUPABASE_ANON_KEY=<publishable key> scripts/deploy.sh          # 预览
SUPABASE_URL=...                       SUPABASE_ANON_KEY=...               scripts/deploy.sh --prod   # 正式
```

脚本先在本地 `flutter build web`（`API_BASE_URL=/api`，同域名，不用 CORS）输出到 `backend/web/`，再把 `backend/` 传给 Vercel。`.vercelignore` 保证 `.env`、本地数据库、测试不会被上传。

以后想改成推 GitHub 自动部署：Vercel 项目 Root Directory 设 `backend`，并打开 “Include files outside the root directory”，`build_web.sh` 会在构建机上装 Flutter 再打包（每次多 2～3 分钟）。Build Command 留空（Project Settings 里填了会覆盖 `pyproject.toml` 里的 build 脚本）。

> Vercel 按 `backend/pyproject.toml` 的 `dependencies` 装包，**不读 `requirements.txt`**。加新依赖两边都要写，`tests/test_deploy_config.py` 会检查。

## 4. 检查

- `https://<网址>/api/health` → `{"status":"ok", ...}`
- 打开网址 → 登录页 → 注册 → （如果开了确认邮件）点邮件里的链接 → 登录 → 新手教程。
- 两个账号互相看不到对方的课程（后端 `tests/test_accounts.py` 在 SQLite 上测的是同一套机制）。

## 5. 手机 App（iOS / Android）

同一套 Flutter 代码、同一个后端和 Supabase，不用改架构，只是打包方式不同：

```bash
cd app
flutter build apk --release \
  --dart-define=API_BASE_URL=https://<网址>/api \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key>
# iOS：flutter build ipa（同样的 --dart-define），需要 Apple 开发者账号签名
```

- App 里 `API_BASE_URL` 必须写完整网址（网页版用的是同域名的 `/api`）。
- 登录态由 `supabase_flutter` 存在手机本地，下次打开自动登录。
- 确认邮件 / 重置密码的链接用 `selfinfinity://login-callback` 打开 App（已在 `AndroidManifest.xml` 和 `Info.plist` 里注册）。
- 麦克风权限两边都已声明（语音模式）。
- 上架应用商店另需：图标、启动图、隐私政策网址、Apple / Google 开发者账号。

## 已知限制

- 上传文件最大 4 MB（Vercel 请求体上限 4.5 MB）。
- Linker（教训卡之间的连线）在响应之后作为后台任务跑；在 Vercel 上如果函数先结束，只是少了连线，不影响别的。
- Postgres 路径还没有在真实 Supabase 上跑过（本机没有 Postgres）；第一次部署后按上面的检查走一遍。
