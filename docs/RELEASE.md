# Release APK / Play Store build

## Kya banta hai

Har push par GitHub Actions ye 3 cheezein banata hai (run page → **Artifacts**):

| Artifact | Kya hai | Kab use karein |
|---|---|---|
| `thekedaar-debug-apk` | Debug APK (~90 MB) | Sirf testing |
| `thekedaar-release-apk` | Release APK, har CPU ke liye alag (~20 MB) | Phone par seedha install / WhatsApp se bhejna. Zyada tar phones: `app-arm64-v8a-release.apk` |
| `thekedaar-release-aab` | `app-release.aab` | Google Play Store par upload |

## Signing key (keystore / JKS)

Release build ek **upload key** se sign hoti hai. Ye key ek baar banti hai aur hamesha wahi rehti hai. Isi key se sign kiya hua naya version purane app ke upar install/update hota hai.

Key ban chuki hai, aur project ke **bahar** rakhi hai (GitHub par kabhi nahi jaati):

```
C:\Users\Devlopment\Thekedaar-signing\
  upload-keystore.p12   ← key (PKCS12 format, .jks ki tarah hi kaam karti hai)
  keystore-base64.txt   ← wahi key text mein, GitHub secret ke liye
  signing-info.txt      ← alias, password, SHA-1 / SHA-256
  upload-cert.pem       ← public certificate (secret nahi)
```

⚠️ **Is folder ka backup rakhein** (pen drive / Google Drive ka private folder), aur password kisi ko na dein.
Key kho gayi to Play Store par app update nahi kar paayenge. Play App Signing on ho to Google se upload key reset karwani padegi, jisme kuch din lagte hain.

## GitHub secrets (ek baar)

GitHub → repo **Thekedaar** → Settings → Secrets and variables → Actions → **New repository secret**:

| Secret name | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `keystore-base64.txt` ka poora content |
| `ANDROID_KEYSTORE_PASSWORD` | `signing-info.txt` mein "Store password" |
| `ANDROID_KEY_ALIAS` | `upload` |
| `GOOGLE_SERVER_CLIENT_ID` | Google Cloud Web client id (Drive backup, PRD D-7) |

Secrets na hon to bhi release APK banti hai, lekin debug key se sign hoti hai. Run mein ek warning aati hai, aur aisi files Play Store par upload nahi karni.

CI keystore ko har run mein secrets se `android/app/upload-keystore.p12` aur `android/key.properties` mein likhta hai. `tool/patch_android.dart` release build ko us key se sign karwata hai.

## Google Drive login ke liye SHA-1

Google Cloud ke **Android OAuth client** mein dono SHA-1 daalne honge:
- **Release key SHA-1:** `signing-info.txt` mein hai. Secrets lagne ke baad har run mein "Release key SHA-1" notice mein bhi dikhta hai.
- **Debug key SHA-1:** CI har run mein naya debug key banata hai, isliye debug APK par Google login kaam nahi karega. Google login release APK par test karein.

## Play Store par pehli baar

1. Google Play Console account banayein (one-time $25 fee).
2. Naya app banayein. Package name `com.thekedaar.thekedaar` hai, jo PRD D-6 tay hone par badal sakte hain. **Pehla upload ke baad package name kabhi nahi badal sakta.**
3. **Play App Signing** on rakhein (default).
4. `thekedaar-release-aab` wali `app-release.aab` upload karein.
5. Har naye version se pehle `pubspec.yaml` mein `version: 0.1.0+1` ka `+1` wala number badhayein (`+2`, `+3`…), warna Play Store upload nahi lega.
