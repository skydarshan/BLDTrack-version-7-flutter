# BldTrack Flutter — Live API + Store Beta guide

## Live API

Production / TestFlight / Play builds always use:

```text
https://api.bldtrack.ai
```

Same backend as the React web app. Phones talk to this URL directly (no local Node, no proxy).

---

## Chrome demo against live API (local machine)

Browsers block CORS from `localhost` → live API. Use the proxy + IPv4:

```bash
cd AvidusProduct-Flutter
chmod +x scripts/run_live_web.sh
./scripts/run_live_web.sh
```

Login screen should show: `API: live (via proxy http://127.0.0.1:8787)`

---

## Android — Play Internal / Closed testing

1. App ID: `ai.bldtrack.avidus_product`
2. Signing: `android/key.properties` + `android/keystore/bldtrack-upload.jks` (gitignored)
3. Build:

```bash
chmod +x scripts/build_store_release.sh
./scripts/build_store_release.sh
```

4. Upload `build/app/outputs/bundle/release/app-release.aab` in Play Console → Testing → Internal testing.

**Keep the keystore + passwords safe.** Losing them blocks app updates on Play.

---

## iOS — TestFlight

1. Bundle ID: `ai.bldtrack.avidusProduct`
2. Apple Developer account + App Store Connect app
3. Open `ios/Runner.xcworkspace` in Xcode → Signing & Capabilities → select your Team
4. Build:

```bash
flutter build ipa --release --dart-define=API_BASE_URL=https://api.bldtrack.ai
```

5. Upload via Xcode Organizer or Transporter → TestFlight → add testers

---

## Checklist before inviting testers

- [ ] `https://api.bldtrack.ai/api/v1/health` returns OK
- [ ] Login works on a real device / TestFlight build
- [ ] Privacy Policy URL ready (Play often requires it)
- [ ] Screenshots for store listings (can add later for Internal testing)
