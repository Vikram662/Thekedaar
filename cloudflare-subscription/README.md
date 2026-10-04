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

## Trigger the app update popup

Set these Worker variables in `wrangler.jsonc` and deploy:

- `APP_LATEST_BUILD`: newest published Flutter build number. If it is greater
  than `AppConfig.appBuildNumber`, the popup appears.
- `APP_MINIMUM_BUILD`: oldest allowed build. A lower installed build makes the
  popup mandatory; otherwise users can choose **Baad mein**.
- `APP_UPDATE_URL`: Play Store or APK download page.
- `APP_UPDATE_MESSAGE`: text displayed in the popup.

For every release, increment both `version: ...+N` in `pubspec.yaml` and
`AppConfig.appBuildNumber`, publish the app, then raise `APP_LATEST_BUILD`.
