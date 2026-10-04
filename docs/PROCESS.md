# Thekedaar App: poora process (step by step)

Ye file aage ke liye hai. Jab bhi APK banana ho, key setup karni ho ya Play Store par daalna ho, yahi steps follow karein.

Repo: https://github.com/Vikram662/Thekedaar
Spec: [PRD_Thekedaar_App.md](../PRD_Thekedaar_App.md) · Release details: [RELEASE.md](RELEASE.md)

---

## 1. Roz ka kaam: code se APK tak

Is computer par Flutter install nahi hai. Saara build GitHub par hota hai.

1. Code badla → commit → `git push origin main`
2. GitHub → repo → **Actions** tab → sabse upar wala **Build** run kholein
3. Run lagbhag 10–15 minute chalta hai. Steps:
   - Analyze (code check) → Test (saare tests) → Debug APK → Release APK → Release AAB
4. Hara ✅ = pass. Run page ke neeche **Artifacts** mein files milengi:

| Artifact | Kis kaam ki |
|---|---|
| `thekedaar-debug-apk` | Testing (badi file, ~90 MB) |
| `thekedaar-release-apk` | Phone par install / WhatsApp par bhejna. Zyada tar phones: `app-arm64-v8a-release.apk` |
| `thekedaar-release-aab` | Sirf Google Play Store upload |

5. Zip download karein → kholein → APK phone par bhejein → install karein ("Install unknown apps" allow karna padega).

### Build laal ❌ ho jaye to

- Run kholein → laal step par click karein. Errors **annotations** mein bhi dikhte hain (run page ke upar "Annotations" box mein).
- Wo error text copy karke Claude ko de dein, ya sirf itna kahein "build check karo". Claude annotations khud padh sakta hai.

---

## 2. Signing key (keystore / JKS): ek baar ka kaam ✅ ho chuka

Release APK ek **upload key** se sign hoti hai. Har naya version **isi key** se sign hona chahiye, warna phone par purane app ke upar update nahi hoga.

Key yahan hai (project ke **bahar**, GitHub par kabhi nahi jaati):

```
C:\Users\admin\Thekedaar-signing\
  upload-keystore.p12   ← asli key (PKCS12 = JKS jaisi hi)
  keystore-base64.txt   ← key text mein (GitHub secret ke liye)
  signing-info.txt      ← alias, PASSWORD, SHA-1, SHA-256
  upload-cert.pem       ← public certificate (secret nahi)
  upload-key.pem        ← private key
```

- Key alias: `upload`
- Valid: 30 saal
- SHA-1: `FB:57:BF:C1:40:E7:43:9E:AA:67:26:EE:5F:36:55:D6:0A:C9:EF:33`
- SHA-256: `A7:FB:F5:EB:B4:2F:AE:4B:9B:55:B9:63:37:1C:6D:E5:EB:90:37:6C:B0:4F:E5:34:F3:AB:E0:C7:2E:59:CB:5D`
- Password: Jo aapne generate karte waqt set kiya hai (use `signing-info.txt` mein likh kar rakh lein).

### ⚠️ Backup zaroori

Is poore folder (`C:\Users\admin\Thekedaar-signing\`) ki copy 2 jagah rakhein, jaise pen drive aur apne Google Drive ka **private** folder.
- Key kho gayi: Play Store par update ke liye Google se key reset karwani padegi (kuch din lagte hain).
- Password kisi ko na dein, WhatsApp par na bhejein, GitHub par na daalein.

---

## 3. GitHub secrets: ek baar ka kaam ⏳ (aapko karna hai)

GitHub → **Thekedaar** repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Har secret ke liye: *Name* likhein, *Secret* mein value paste karein, **Add secret**.

| Name | Value kahan se |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `C:\Users\admin\Thekedaar-signing\keystore-base64.txt` kholein (Notepad) → Ctrl+A → Ctrl+C → paste |
| `ANDROID_KEYSTORE_PASSWORD` | Jo password aapne create karte waqt daala tha |
| `ANDROID_KEY_ALIAS` | `upload` |
| `GOOGLE_SERVER_CLIENT_ID` | Section 4 ke baad milega (Drive backup ke liye) |

Check kaise karein: secrets daalne ke baad agla build chalega. Usme **"Release key SHA-1"** wala notice dikhega, aur "debug key" wali warning **nahi** aayegi.

Secrets na hon to bhi release APK banti hai, lekin debug key se. Wo sirf testing ke liye hai, Play Store ke liye nahi.

---

## 4. Google Drive backup chalu karna (PRD D-7) ⏳

Iske bina app chalta hai, bas Drive backup band rehta hai.

1. https://console.cloud.google.com → upar project dropdown → **New Project** → naam `Thekedaar` → Create
2. **APIs & Services → Library** → "Google Drive API" search → **Enable**
3. **APIs & Services → OAuth consent screen**
   - User type: External → app name `Thekedaar`, apna email
   - Scopes: `.../auth/drive.file` add karein
   - Test users: apna Gmail add karein (jab tak app "Testing" mode mein hai)
4. **APIs & Services → Credentials → Create credentials → OAuth client ID** (2 baar):
   - **Android** type
     - Package name: `com.thekedaar.thekedaar`
     - SHA-1: `FB:57:BF:C1:40:E7:43:9E:AA:67:26:EE:5F:36:55:D6:0A:C9:EF:33`
   - **Web application** type → naam kuch bhi → Create → jo **Client ID** mile (`xxxx.apps.googleusercontent.com`) use copy karein
5. GitHub secret `GOOGLE_SERVER_CLIENT_ID` = wo Web Client ID (Section 3)
6. Naya build → **release APK** install karein → Settings → Backup & restore → Connect Google Drive

Note: Google login sirf **release APK** par chalega. Debug APK ki key har build mein badalti hai, isliye usme login fail hoga.

---

## 5. Play Store par pehli baar ⏳

1. https://play.google.com/console → developer account (one-time $25)
2. **Create app** → naam, language, App/Free
3. Package name `com.thekedaar.thekedaar` hoga. ⚠️ Pehle upload ke baad ye **kabhi nahi badalta**, isliye pehle PRD D-6 (app ka naam/package) final kar lein.
4. **Play App Signing**: on rehne dein (default)
5. Testing → Internal testing → Create release → `thekedaar-release-aab` wali `app-release.aab` upload
6. Privacy policy, data safety form, screenshots bharein → review ke liye bhejein

### Har naye version se pehle

`pubspec.yaml` mein version badhayein:

```
version: 0.1.0+1   →   version: 0.1.1+2
```

`+` ke baad wala number har upload par **badhna hi chahiye**, warna Play Store file reject karega.

---

## 6. Backup kaise kaam karta hai (yaad ke liye)

- Data sirf phone mein (SQLite). Drive par backup: din mein 4 baar, data badalne ke 2 min baad, aur internet wapas aate hi.
- Sab encrypted hai: **Backup Password** + **Recovery Key** (setup ke waqt app dikhata hai, kagaz par likh lein).
- Photos (kharche ke bill) bhi encrypted hokar Drive ke `files/` folder mein jaati hain, har photo ek baar.
- Naya phone: app install → "Already using Thekedaar?" → Restore → wahi Google account → password ya recovery key.
- "Download backup file" (.tkbak) mein sirf data hai, **photos nahi**.

---

## Checklist (abhi ki sthiti)

- [x] Code Phase 1 + Lena/Dena + Expenses + Suppliers
- [x] Release keystore bana
- [ ] Keystore folder ka backup (pen drive + private Drive)
- [ ] GitHub secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`
- [ ] Google Cloud setup + `GOOGLE_SERVER_CLIENT_ID` (D-7)
- [ ] App name / package id final (D-6)
- [ ] Phone par poora test
- [ ] Play Store account + pehla internal test release
