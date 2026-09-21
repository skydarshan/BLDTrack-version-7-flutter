# Avidus Product — Flutter (Phase 1)

Mobile client for Avidus / BldTrack using the **same backend** as the React web app.

## Phase 1 scope

- Organization registration (`POST /auth/register-organization`)
- Login (`POST /auth/login`)
- Dashboard shell with session restore (`GET /auth/me`)
- Logout (`POST /auth/logout`)
- Secure token storage + auth-gated routing

## Requirements

- Flutter 3.38+ / Dart 3.10+
- Backend reachable at the configured API host

## Run

```bash
cd AvidusProduct-Flutter

# Default API: https://api.bldtrack.ai
flutter run

# Or point to another host (no trailing slash):
flutter run --dart-define=API_BASE_URL=https://api.bldtrack.ai
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000   # Android emulator → host localhost
```

## Project structure

```text
lib/
  main.dart
  app.dart
  core/           # API client, config, theme, storage
  features/
    auth/         # login, register, models, provider
    dashboard/    # post-login home
  router/         # go_router + auth redirects
```

## Auth flow

1. Register or login → receive `accessToken` (+ `refreshToken` on login)
2. Token saved via `flutter_secure_storage`
3. All API calls send `Authorization: Bearer <token>`
4. `401` clears session and returns to login
5. Cold start restores token and refreshes profile via `/auth/me`

## Verify manually

1. Register a new org (3-step form) → land on Dashboard
2. Logout → Login with same credentials → Dashboard shows name/email/role
3. Kill and reopen app → still authenticated (token restore)
