# Thekedaar App

Offline Android app (Flutter) for contractors of every trade. Full spec: [PRD_Thekedaar_App.md](PRD_Thekedaar_App.md).

## Bina Flutter install kiye kaise chalayein

Is computer par Flutter install nahi hai. Code GitHub par cloud mein check aur build hota hai.

1. GitHub par ek **private** repo banayein aur ye folder usme push karein.
2. Har push par **Actions → Build** apne aap chalega:
   - Android files generate (`flutter create`)
   - drift code generate (`build_runner`)
   - `flutter analyze` + saare tests
   - debug APK build
3. Run khatam hone par **Artifacts → thekedaar-debug-apk** download karein, zip kholein aur `app-debug.apk` phone par install karein ("Install unknown apps" allow karna padega).

Browser mein code edit + run karne ke liye **GitHub Codespaces** ya **Firebase Studio** bhi use kar sakte hain (dono mein Flutter mil jaata hai).

## Agar kabhi Flutter install karein

```
flutter create . --platforms=android --org com.thekedaar --project-name thekedaar
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run
```

## Structure

```
lib/
  app/        theme (PRD E3 tokens), router, bottom tabs
  core/
    db/       drift tables (PRD Part F), enums, providers
    seed/     trade-wise default data loader (PRD C0, Part J)
    utils/    paise, milli-qty, measurement (BL-16), phone, dates
    widgets/  shared widgets
  features/
    onboarding/  business + trade selection
    dashboard/
    workers/     worker list, add worker (daily / monthly / piece-rate)
    khata/       wage calculator (I-S1, I-S3)
assets/seed/  common.json + one JSON per trade
test/
```

## Rules

- Paisa hamesha `int` paise mein, qty `int` milli-units mein. `double` kabhi nahi.
- Enum values DB mein naam se save hote hain. Naam badalne se pehle migration likhein.
- Schema badle to `AppDatabase.schemaVersion` badhayein aur migration step jodein.
- Generated files (`*.g.dart`) commit nahi hoti, CI banata hai.
