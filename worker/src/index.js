/**
 * 反馈在线提交后端。
 *
 * 当前能力：
 * 1. 接收 Flutter 客户端提交的反馈 JSON；
 * 2. 做基础字段校验与长度限制；
 * 3. 写入 R2，key 为 feedback/YYYY-MM/YYYY-MM-DD-<随机>.json。
 *
 * 后续可按 backlog 增加：限流、GitHub Issue 代发、邮件通知等。
 */

const ALLOWED_TYPES = new Set(['Bug', '建议']);
const MAX_TITLE_LENGTH = 200;
const MAX_DESCRIPTION_LENGTH = 5000;
const MAX_LOG_TAIL_LENGTH = 8 * 1024;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'POST' && url.pathname === '/api/feedback') {
      return handleFeedback(request, env);
    }

    if (request.method === 'GET' && url.pathname === '/health') {
      return Response.json({ ok: true });
    }

    return new Response('not found', { status: 404 });
  },
};

async function handleFeedback(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return Response.json(
      { ok: false, error: '请求体必须是合法 JSON' },
      { status: 400 },
    );
  }

  const errors = validate(body);
  if (errors.length > 0) {
    return Response.json(
      { ok: false, errors },
      { status: 400 },
    );
  }

  const now = new Date();
  const yyyy = now.getUTCFullYear();
  const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(now.getUTCDate()).padStart(2, '0');
  const key = `feedback/${yyyy}-${mm}/${yyyy}-${mm}-${dd}-${crypto.randomUUID()}.json`;

  const payload = {
    type: body.type,
    title: body.title.trim(),
    description: body.description.trim(),
    appVersion: body.appVersion,
    platform: body.platform,
    contentDataVersion: body.contentDataVersion,
    schemaVersions: body.schemaVersions,
    logTail: body.logTail,
    clientTs: body.clientTs,
    receivedAt: now.toISOString(),
  };

  await env.FEEDBACK_BUCKET.put(
    key,
    JSON.stringify(payload, null, 2),
    { httpMetadata: { contentType: 'application/json' } },
  );

  return Response.json({ ok: true, id: key });
}

function validate(body) {
  const errors = [];

  if (!body || typeof body !== 'object') {
    return ['请求体必须是对象'];
  }

  if (!ALLOWED_TYPES.has(body.type)) {
    errors.push('type 必须是 Bug 或 建议');
  }
  if (typeof body.title !== 'string' || body.title.trim().length === 0) {
    errors.push('title 不能为空');
  } else if (body.title.trim().length > MAX_TITLE_LENGTH) {
    errors.push(`title 不能超过 ${MAX_TITLE_LENGTH} 字`);
  }
  if (typeof body.description !== 'string' || body.description.trim().length === 0) {
    errors.push('description 不能为空');
  } else if (body.description.trim().length > MAX_DESCRIPTION_LENGTH) {
    errors.push(`description 不能超过 ${MAX_DESCRIPTION_LENGTH} 字`);
  }
  if (typeof body.logTail !== 'string') {
    errors.push('logTail 必须是字符串');
  } else if (body.logTail.length > MAX_LOG_TAIL_LENGTH) {
    errors.push(`logTail 不能超过 ${MAX_LOG_TAIL_LENGTH} 字符`);
  }

  return errors;
}
