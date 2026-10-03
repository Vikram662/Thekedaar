# Thekedaar App

Offline Android app (Flutter) for contractors of every trade. Full spec: [PRD_Thekedaar_App.md](PRD_Thekedaar_App.md).

Phase 1 (MVP) code is complete: app lock, trade setup, workers & wages, daily attendance, piece-rate, khata & settlement with pay-slip PDF, billing (quotation / bill / payments / PDF share), Google Drive auto backup & restore, dashboard.

## Bina Flutter install kiye kaise chalayein

Is computer par Flutter install nahi hai. Code GitHub par cloud mein check aur build hota hai.

1. GitHub par ek **private** repo banayein aur ye folder usme push karein.
2. Har push par **Actions → Build** apne aap chalega:
   - Android files generate (`flutter create`) + patch (`tool/patch_android.dart`: fingerprint, permissions, minSdk 24)
   - drift code generate (`build_runner`)
   - `flutter analyze` + saare tests
   - debug APK build
3. Run khatam hone par **Artifacts → thekedaar-debug-apk** download karein, zip kholein aur `app-debug.apk` phone par install karein.

## Google Drive backup chalu karna (PRD D-7)

Backup ke liye Google Cloud mein ek baar setup chahiye:

1. Google Cloud Console → naya project → **Google Drive API** enable.
2. OAuth consent screen banayein (scope: `drive.file`).
3. OAuth client banayein:
   - **Android** client: package `com.thekedaar.thekedaar` + debug/release keystore ka SHA-1
   - **Web application** client: iska client id hi `GOOGLE_SERVER_CLIENT_ID` hai
4. GitHub repo → Settings → Secrets → Actions → `GOOGLE_SERVER_CLIENT_ID` naam se Web client id daalein.

Ye id na ho to app chalta hai, bas Backup screen "not switched on" dikhati hai (file se restore phir bhi hota hai).

## Agar kabhi Flutter install karein

```
flutter create . --platforms=android --org com.thekedaar --project-name thekedaar
dart run tool/patch_android.dart
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
```

## Structure

```
lib/
  app/        theme (PRD E3), router (all screens), bottom tabs
  core/
    backup/   engine, Drive store, keyring + .tkbak format, scheduler, restore
    db/       drift tables (PRD Part F), audit log, app_meta store
    pdf/      shared PDF helpers + share
    security/ PIN hashing, secure storage
    seed/     trade-wise default data (PRD C0, Part J)
    settings/ business rules
    utils/    paise, milli-qty, measurement, phone, dates
    widgets/  numpad, pickers, common widgets
  features/
    onboarding/ dashboard/ workers/ attendance/ khata/ billing/
    backup/ settings/ lock/
assets/seed/  common.json + one JSON per trade
tool/         patch_android.dart
test/
```

## Rules

- Paisa hamesha `int` paise mein, qty `int` milli-units mein. `double` kabhi nahi.
- Khata entries kabhi edit/delete nahi hoti, reversal entry banti hai.
- Enum values DB mein naam se save hote hain. Naam badalne se pehle migration likhein.
- Schema badle to `AppDatabase.currentSchemaVersion` badhayein aur migration step jodein.
- Secrets (PIN hash, backup key, device id) secure storage mein, DB mein nahi.
- Generated files (`*.g.dart`) commit nahi hoti, CI banata hai.
