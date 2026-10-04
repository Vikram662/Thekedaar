// Secure Razorpay boundary for the Thekedaar Android app.
const JSON_HEADERS = { 'content-type': 'application/json; charset=utf-8' };

export default {
  async fetch(request, env) {
    const cors = {
      'access-control-allow-origin': env.ALLOWED_ORIGIN || '*',
      'access-control-allow-headers':
        'authorization, content-type, x-razorpay-signature',
      'access-control-allow-methods': 'GET, POST, OPTIONS',
    };
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }
    try {
      const path = new URL(request.url).pathname;
      let response;
      if (request.method === 'GET' && path === '/health') {
        response = ok({ service: 'thekedaar-subscription-api' });
      } else if (request.method === 'GET' && path === '/v1/app-config') {
        response = appConfig(env);
      } else if (request.method === 'POST' && path === '/v1/install') {
        response = await install(request, env);
      } else if (request.method === 'POST' && path === '/v1/notifications/token') {
        response = await updateNotificationToken(request, env);
      } else if (request.method === 'POST' && path === '/v1/subscriptions') {
        response = await createSubscription(request, env);
      } else if (
        request.method === 'GET' &&
        path === '/v1/subscriptions/status'
      ) {
        response = await subscriptionStatus(request, env);
      } else if (
        request.method === 'POST' &&
        path === '/v1/subscriptions/link'
      ) {
        response = await linkSubscription(request, env);
      } else if (
        request.method === 'POST' &&
        path === '/v1/subscriptions/cancel'
      ) {
        response = await cancelSubscription(request, env);
      } else if (
        request.method === 'POST' &&
        path === '/v1/webhooks/razorpay'
      ) {
        response = await razorpayWebhook(request, env);
      } else {
        response = fail(404, 'not_found', 'Endpoint not found.');
      }
      addHeaders(response, cors);
      return response;
    } catch (error) {
      console.error(error);
      const response =
        error instanceof ApiError
          ? fail(error.status, error.code, error.message)
          : fail(500, 'internal_error', 'Something went wrong.');
      addHeaders(response, cors);
      return response;
    }
  },
};

async function install(request, env) {
  const body = await bodyJson(request);
  const installId = requiredString(body.installId, 'installId', 80);
  const name = requiredString(body.name, 'name', 120);
  const phone = optionalString(body.phone, 20);
  const fcmToken = optionalString(body.fcmToken, 4096);
  if (!/^[a-zA-Z0-9-]{16,80}$/.test(installId)) {
    throw new ApiError(400, 'invalid_install', 'Invalid install identifier.');
  }

  let row = await env.DB.prepare(
    'SELECT * FROM installs WHERE install_id = ?',
  )
    .bind(installId)
    .first();
  if (!row) {
    const customer = await razorpay(env, '/customers', 'POST', {
      name,
      ...(phone ? { contact: phone } : {}),
      fail_existing: '0',
      notes: { thekedaar_install_id: installId },
    });
    await env.DB.prepare(
      `INSERT INTO installs
       (install_id, customer_id, name, phone, fcm_token, platform,
        notification_updated_at, updated_at)
       VALUES (?, ?, ?, ?, ?, 'android', ?, ?)`,
    )
      .bind(installId, customer.id, name, phone, fcmToken,
        fcmToken ? epoch() : null, epoch())
      .run();
    row = await env.DB.prepare(
      'SELECT * FROM installs WHERE install_id = ?',
    )
      .bind(installId)
      .first();
  } else {
    await env.DB.prepare(
      `UPDATE installs SET name = ?, phone = ?,
       fcm_token = COALESCE(?, fcm_token),
       notification_updated_at = CASE WHEN ? IS NULL
         THEN notification_updated_at ELSE ? END,
       updated_at = ? WHERE install_id = ?`,
    )
      .bind(name, phone, fcmToken, fcmToken, epoch(), epoch(), installId)
      .run();
    row = await env.DB.prepare(
      'SELECT * FROM installs WHERE install_id = ?',
    )
      .bind(installId)
      .first();
  }
  return ok({
    token: await signToken(
      { sub: installId, exp: epoch() + 90 * 86400 },
      env.APP_TOKEN_SECRET,
    ),
    customerId: row.customer_id,
    subscriptionId: row.subscription_id,
    status: row.subscription_status,
    user: { installId: row.install_id, name: row.name, phone: row.phone },
  });
}

async function updateNotificationToken(request, env) {
  const user = await authenticated(request, env);
  const body = await bodyJson(request);
  const fcmToken = requiredString(body.fcmToken, 'fcmToken', 4096);
  await env.DB.prepare(
    `UPDATE installs SET fcm_token = ?, platform = 'android',
     notification_updated_at = ?, updated_at = ? WHERE install_id = ?`,
  )
    .bind(fcmToken, epoch(), epoch(), user.install_id)
    .run();
  return ok({ updated: true });
}

async function createSubscription(request, env) {
  const user = await authenticated(request, env);
  if (
    user.subscription_id &&
    !['cancelled', 'expired', 'completed'].includes(user.subscription_status)
  ) {
    const current = await razorpay(
      env,
      `/subscriptions/${encodeURIComponent(user.subscription_id)}`,
    );
    return checkout(current, env);
  }
  const trialEligible = !user.subscription_created_at;
  const subscription = await razorpay(env, '/subscriptions', 'POST', {
    plan_id: env.RAZORPAY_PLAN_ID,
    total_count: 120,
    quantity: 1,
    // Authorise the recurring mandate now; start paid billing after the trial.
    ...(trialEligible ? { start_at: epoch() + 5 * 86400 } : {}),
    customer_notify: 1,
    notes: { thekedaar_install_id: user.install_id, trial_days: '5' },
  });
  await env.DB.prepare(
    `UPDATE installs SET subscription_id = ?, subscription_status = ?,
     subscription_created_at = ?, updated_at = ? WHERE install_id = ?`,
  )
    .bind(
      subscription.id,
      subscription.status || 'created',
      subscription.created_at || epoch(),
      epoch(),
      user.install_id,
    )
    .run();
  return checkout(subscription, env, trialEligible);
}

async function subscriptionStatus(request, env) {
  const user = await authenticated(request, env);
  if (!user.subscription_id) {
    return ok({
      status: 'none',
      active: false,
      trialEligible: !user.subscription_created_at,
    });
  }
  const subscription = await razorpay(
    env,
    `/subscriptions/${encodeURIComponent(user.subscription_id)}`,
  );
  await updateSubscription(
    env,
    subscription.id,
    subscription.status,
    null,
    subscription.created_at,
  );
  return ok({ ...statusPayload(subscription), trialEligible: false });
}

async function linkSubscription(request, env) {
  const user = await authenticated(request, env);
  const body = await bodyJson(request);
  const subscriptionId = requiredString(
    body.subscriptionId,
    'subscriptionId',
    80,
  );
  if (!/^sub_[a-zA-Z0-9]+$/.test(subscriptionId)) {
    throw new ApiError(400, 'invalid_subscription', 'Invalid subscription ID.');
  }
  const subscription = await razorpay(
    env,
    `/subscriptions/${encodeURIComponent(subscriptionId)}`,
  );
  if (!subscription.customer_id || !user.phone) {
    throw new ApiError(
      403,
      'cannot_verify_owner',
      'Subscription ownership could not be verified.',
    );
  }
  const customer = await razorpay(
    env,
    `/customers/${encodeURIComponent(subscription.customer_id)}`,
  );
  if (digits(customer.contact) !== digits(user.phone)) {
    throw new ApiError(
      403,
      'owner_mismatch',
      'This subscription belongs to another mobile number.',
    );
  }
  await env.DB.prepare(
    `UPDATE installs SET subscription_id = ?, subscription_status = ?,
     subscription_created_at = ?, updated_at = ? WHERE install_id = ?`,
  )
    .bind(
      subscription.id,
      subscription.status,
      subscription.created_at || epoch(),
      epoch(),
      user.install_id,
    )
    .run();
  return ok(statusPayload(subscription));
}

async function cancelSubscription(request, env) {
  const user = await authenticated(request, env);
  if (!user.subscription_id) {
    throw new ApiError(409, 'no_subscription', 'No subscription is linked.');
  }
  const subscription = await razorpay(
    env,
    `/subscriptions/${encodeURIComponent(user.subscription_id)}/cancel`,
    'POST',
    { cancel_at_cycle_end: 0 },
  );
  await updateSubscription(
    env,
    subscription.id,
    subscription.status || 'cancelled',
  );

  return ok({ ...statusPayload(subscription), trialEligible: false });
}

async function razorpayWebhook(request, env) {
  const raw = await request.text();
  const signature = request.headers.get('x-razorpay-signature') || '';
  if (!await verifyHmac(raw, signature, env.RAZORPAY_WEBHOOK_SECRET)) {
    throw new ApiError(401, 'invalid_signature', 'Invalid webhook signature.');
  }
  const event = JSON.parse(raw);
  const subscription = event.payload?.subscription?.entity;
  const payment = event.payload?.payment?.entity;
  const subscriptionId = subscription?.id || payment?.subscription_id;
  if (subscriptionId) {
    await updateSubscription(
      env,
      subscriptionId,
      subscription?.status || statusFromEvent(event.event),
      payment?.id || null,
      subscription?.created_at,
    );
  }
  return ok({ received: true });
}

function checkout(subscription, env, trialEligible = false) {
  return ok({
    keyId: env.RAZORPAY_KEY_ID,
    subscriptionId: subscription.id,
    status: subscription.status,
    trialEndsAt: subscription.start_at || null,
    trialEligible,
  });
}

function statusPayload(subscription) {
  const status = subscription.status || 'unknown';
  return {
    subscriptionId: subscription.id,
    status,
    active: ['active', 'authenticated'].includes(status),
    currentEnd: subscription.current_end || null,
    trialEndsAt: subscription.start_at || null,
  };
}

function appConfig(env) {
  const latestBuild = positiveInteger(env.APP_LATEST_BUILD, 1);
  const minimumBuild = positiveInteger(env.APP_MINIMUM_BUILD, 1);
  return ok({
    latestBuild,
    minimumBuild: Math.min(minimumBuild, latestBuild),
    updateUrl: env.APP_UPDATE_URL || '',
    message: env.APP_UPDATE_MESSAGE ||
      'Thekedaar ka naya version available hai. Abhi update karein.',
  });
}

function positiveInteger(value, fallback) {
  const parsed = Number.parseInt(String(value || ''), 10);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}

async function updateSubscription(
  env,
  id,
  status,
  paymentId = null,
  createdAt = null,
) {
  const sets = ['subscription_status = ?', 'updated_at = ?'];
  const values = [status || 'unknown', epoch()];
  if (paymentId) {
    sets.push('latest_payment_id = ?');
    values.push(paymentId);
  }
  if (createdAt) {
    sets.push(
      'subscription_created_at = COALESCE(subscription_created_at, ?)',
    );
    values.push(createdAt);
  }
  values.push(id);
  await env.DB.prepare(
    `UPDATE installs SET ${sets.join(', ')} WHERE subscription_id = ?`,
  )
    .bind(...values)
    .run();
}

async function authenticated(request, env) {
  const header = request.headers.get('authorization') || '';
  if (!header.startsWith('Bearer ')) {
    throw new ApiError(401, 'unauthorized', 'Installation is not registered.');
  }
  const token = await verifyToken(header.slice(7), env.APP_TOKEN_SECRET);
  if (!token || token.exp < epoch()) {
    throw new ApiError(401, 'token_expired', 'Session expired.');
  }
  const row = await env.DB.prepare(
    'SELECT * FROM installs WHERE install_id = ?',
  )
    .bind(token.sub)
    .first();
  if (!row) {
    throw new ApiError(401, 'unknown_install', 'Installation was not found.');
  }
  return row;
}

async function razorpay(env, path, method = 'GET', body) {
  const response = await fetch(`https://api.razorpay.com/v1${path}`, {
    method,
    headers: {
      authorization: `Basic ${btoa(
        `${env.RAZORPAY_KEY_ID}:${env.RAZORPAY_KEY_SECRET}`,
      )}`,
      'content-type': 'application/json',
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error('Razorpay API error', response.status, data?.error?.code);
    throw new ApiError(
      502,
      'payment_provider_error',
      data?.error?.description || 'Payment provider request failed.',
    );
  }
  return data;
}

async function signToken(payload, secret) {
  const encoded = base64url(JSON.stringify(payload));
  return `${encoded}.${await hmac(encoded, secret)}`;
}

async function verifyToken(token, secret) {
  const [payload, signature, extra] = token.split('.');
  if (
    !payload ||
    !signature ||
    extra ||
    !safeEqual(await hmac(payload, secret), signature)
  ) {
    return null;
  }
  try {
    return JSON.parse(fromBase64url(payload));
  } catch (_) {
    return null;
  }
}

async function verifyHmac(value, signature, secret) {
  return signature.length > 0 && safeEqual(await hmac(value, secret), signature);
}

async function hmac(value, secret) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value)),
  );
  return [...bytes]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function base64url(value) {
  const bytes = new TextEncoder().encode(value);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/, '');
}

function fromBase64url(value) {
  const padded =
    value.replaceAll('-', '+').replaceAll('_', '/') +
    '='.repeat((4 - (value.length % 4)) % 4);
  const binary = atob(padded);
  return new TextDecoder().decode(
    Uint8Array.from(binary, (character) => character.charCodeAt(0)),
  );
}

function safeEqual(left, right) {
  if (left.length !== right.length) return false;
  let result = 0;
  for (let index = 0; index < left.length; index++) {
    result |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return result === 0;
}

function statusFromEvent(event) {
  const value = String(event || '').split('.').at(-1);
  return value === 'charged' ? 'active' : value || 'unknown';
}

function digits(value) {
  return String(value || '')
    .replace(/\D/g, '')
    .slice(-10);
}

function epoch() {
  return Math.floor(Date.now() / 1000);
}

async function bodyJson(request) {
  try {
    return await request.json();
  } catch (_) {
    throw new ApiError(400, 'invalid_json', 'Request body must be valid JSON.');
  }
}

function requiredString(value, field, maxLength) {
  if (
    typeof value !== 'string' ||
    !value.trim() ||
    value.trim().length > maxLength
  ) {
    throw new ApiError(400, 'invalid_request', `${field} is required.`);
  }
  return value.trim();
}

function optionalString(value, maxLength) {
  if (value == null || value === '') return null;
  if (typeof value !== 'string' || value.trim().length > maxLength) {
    throw new ApiError(400, 'invalid_request', 'Invalid text value.');
  }
  return value.trim();
}

function addHeaders(response, headers) {
  for (const [key, value] of Object.entries(headers)) {
    response.headers.set(key, value);
  }
}

function ok(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: JSON_HEADERS,
  });
}

function fail(status, code, message) {
  return new Response(JSON.stringify({ error: { code, message } }), {
    status,
    headers: JSON_HEADERS,
  });
}

class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
