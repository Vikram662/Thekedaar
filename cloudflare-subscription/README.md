# Thekedaar Subscription API

Secure Cloudflare Worker boundary between the Flutter app and Razorpay. Business
records never pass through this service; it stores only payment identifiers and
subscription state.

## Deploy

1. Create D1 database `thekedaar-subscriptions` and paste its database ID in
   `wrangler.jsonc`.
2. `npm install`
3. `npx wrangler login`
4. `npm run db:remote`
5. Add encrypted secrets (never commit or paste them into chat):

   ```text
   npx wrangler secret put RAZORPAY_KEY_ID
   npx wrangler secret put RAZORPAY_KEY_SECRET
   npx wrangler secret put RAZORPAY_PLAN_ID
   npx wrangler secret put RAZORPAY_WEBHOOK_SECRET
   npx wrangler secret put APP_TOKEN_SECRET
   ```

6. `npm run deploy`
7. Razorpay webhook URL: `https://<worker>.workers.dev/v1/webhooks/razorpay`
   Enable subscription authenticated/activated/charged/pending/halted/cancelled
   and payment captured/failed events. Use the same webhook secret.

Use Razorpay Test Mode keys first. Configure the Flutter build with
`--dart-define=SUBSCRIPTION_API_URL=https://<worker>.workers.dev`.