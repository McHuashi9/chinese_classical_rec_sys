# Worker：反馈在线提交

接收 Flutter 客户端提交的反馈，并写入 R2。

## 本地运行

```bash
cd worker
wrangler dev
```

默认监听 `http://localhost:8787`。

## 测试

```bash
curl -X POST http://localhost:8787/api/feedback \
  -H 'content-type: application/json' \
  -d '{
    "type":"Bug",
    "title":"测试",
    "description":"hello",
    "appVersion":"1.1.0",
    "platform":"Linux",
    "contentDataVersion":"data-20260816-213645",
    "schemaVersions":"用户 1 · 内容 1",
    "logTail":"line1",
    "clientTs":"2026-08-18T00:00:00.000Z"
  }'
```

预期返回：

```json
{ "ok": true, "id": "feedback/2026-08/2026-08-18-xxxx.json" }
```

## R2 数据查看

对象路径格式：

```text
feedback/YYYY-MM/YYYY-MM-DD-<uuid>.json
```

### 方式一：Cloudflare 控制台（最简单）

进入 Cloudflare Dashboard → R2 → `feedback-telemetry` bucket，按 `feedback/` 前缀浏览。

### 方式二：wrangler 下载单个对象

如果你知道对象 key：

```bash
wrangler r2 object get feedback-telemetry/feedback/2026-08/2026-08-18-xxxx.json --file feedback.json
cat feedback.json
```

### 方式三：S3 兼容工具（推荐定期查看）

R2 支持 S3 API。可以用 `aws cli` 或 `rclone` 配置后定期同步/列举：

```bash
# 以 aws cli 为例，先配置 R2 endpoint 和 Access Key
aws s3 ls s3://feedback-telemetry/feedback/ --recursive
aws s3 cp s3://feedback-telemetry/feedback/ ./feedback-archive/ --recursive
```

需要提前在 Cloudflare R2 创建 API Token（权限：R2 读）。

## 部署

```bash
wrangler r2 bucket create feedback-telemetry
wrangler deploy
```

部署后把正式 Worker URL 配置到 Flutter 客户端的 `FeedbackConfig.workerBaseUrl`。

## 后续

- 限流
- GitHub Issue 代发
- 邮件通知
- 管理端查看接口
