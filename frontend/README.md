# ChangaSmart — Frontend (Flutter)

A mobile UI for ChangaSmart: create a fundraising project, track a Main
Contribution and any number of Harambee sessions, record M-PESA payments,
run reconciliation, resolve ambiguous ("paid on behalf of") cases, and
generate copy-paste-ready WhatsApp updates.

The backend (FastAPI, in `../backend`) is the single source of truth for
everything — reconciliation logic, financial totals, WhatsApp text. This
app is a thin client over its HTTP API (see `../backend/app/main.py`).

## Test it on your Android phone

### 1. Start the backend

```bash
cd ../backend
source ../.venv/bin/activate   # create the venv first if you haven't: python3 -m venv ../.venv && pip install -r requirements.txt
AGENT_MODE=mock uvicorn app.main:app --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` is required so your phone (not just this computer) can
reach it. `AGENT_MODE=mock` (the default anyway — see `.env.example`)
means the whole app works with zero AWS/Bedrock calls, including
ambiguous-case reconciliation.

Verify it's up: `curl http://localhost:8000/health` should return
`{"status":"ok"}`.

### 2. Find your computer's local IP address

```bash
# Linux
hostname -I | awk '{print $1}'
# or
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1

# macOS
ipconfig getifaddr en0

# Windows
ipconfig   # look for "IPv4 Address" under your active adapter
```

You want something like `192.168.1.155` — a private LAN address. Your
phone and computer **must be on the same Wi-Fi network** for this to work.

### 3. Start the Flutter app pointed at that IP

```bash
cd frontend
flutter pub get
flutter run --dart-define=API_BASE_URL=http://YOUR_COMPUTER_IP:8000
```

Replace `YOUR_COMPUTER_IP` with the address from step 2, e.g.:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.155:8000
```

### 4. Connect your Android phone

1. Enable Developer Options on your phone (tap Build Number 7 times in
   Settings → About Phone), then enable USB Debugging.
2. Plug the phone into your computer via USB.
3. Run `flutter devices` — your phone should be listed. If Android Studio
   prompts you to authorize the computer, accept it on the phone.
4. Run the command from step 3. `flutter run` will build and install a
   debug APK onto the connected device and launch it.

Prefer a wireless build? Build the APK once and copy it over:

```bash
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.155:8000
# APK is at build/app/outputs/flutter-apk/app-debug.apk
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### 5. Test with mock data

`AGENT_MODE=mock` on the backend means the entire flow — including the
core "payment on behalf of someone else" reconciliation case — works with
no AWS credentials. A good end-to-end path to try:

1. **New Project** → name it, give it a target amount.
2. You land on the project dashboard → **Add Main Contribution**.
3. Open it → **Contributors** → add a few, e.g. "Jane Wanjiku" expecting
   KSh 3,000.
4. Back out → **Transactions** → **Record Payment**: sender "Anne Otieno",
   amount 3,000 (simulating someone paying on Jane's behalf).
5. **Reconcile Contributions** — this transaction will show up under
   "Needs your confirmation", *not* auto-credited to Jane.
6. Tap **Credit Jane Wanjiku** — the report updates immediately.
7. Try **WhatsApp Update** → **Copy** to grab a ready-to-paste update.
8. Back on the project dashboard, **Add Harambee** to try a second,
   independent collection with its own target/progress, and **Close
   Harambee** when done.

Alternatively, seed a full example dataset via the backend's existing
script (run against `http://localhost:8000`, i.e. from the same computer
running the backend, not from the phone):

```bash
cd ..
python sample-data/seed.py
```

Then pull-to-refresh the Home screen on your phone to see it.

### 6. Test the M-PESA Inbox with your phone's real SMS

This is the one part of the app that genuinely needs a **physical Android
phone** — the emulator has no real SMS history, so it will correctly show
an empty inbox there (see "Demo Data vs. Phone SMS" below).

1. Open a project → a collection → **M-PESA Inbox**.
2. Grant SMS permission when prompted (read-only; the app never sends or
   monitors SMS -- see Privacy below).
3. Your phone's existing M-PESA messages appear immediately, newest
   first -- no need to wait for a new SMS.
4. Scroll through them.
5. Tap one to see the **raw SMS** (kept on-device only) alongside what was
   parsed from it.
6. Tap **Select**, choose one or more "Not imported" messages (already-
   imported ones and unparsed ones can't be selected).
7. Tap **Import Selected**, review the preview, confirm.
8. You land on the existing reconciliation result screen -- exact matches
   confirm automatically, ambiguous ones need your review, exactly as with
   manually recorded payments.
9. Re-open the M-PESA Inbox: the messages you just imported now show
   **Already imported** and can't be selected again -- try importing the
   same message twice to confirm it's a no-op.

### Demo Data vs. Phone SMS

Everything else in this app (projects, contributors, sample data) is
**Demo Data** -- it works identically on an emulator or a phone, backed by
the mock/demo backend. The **M-PESA Inbox** is different: it reads
**Phone SMS**, a real, per-device data source that only a physical Android
phone has. On an emulator (or a phone with no M-PESA messages yet) it
correctly shows "No phone SMS available" rather than any fabricated data
-- the app never invents SMS to make the screen look populated.

## Troubleshooting

**"Unable to load projects" / "Could not reach the backend at http://..."**
on the Home screen:
- Confirm the backend is actually running: `curl http://localhost:8000/health`
  from your computer.
- Confirm you started uvicorn with `--host 0.0.0.0`, not the default
  `127.0.0.1` (which only accepts connections from the same machine).
- Confirm `API_BASE_URL` used a real LAN IP, not `localhost` or
  `127.0.0.1` — on a physical phone those refer to the phone itself.
- Confirm phone and computer are on the **same Wi-Fi network** (not phone
  on mobile data, not computer on a different/guest network).
- Some routers isolate devices from each other ("AP/client isolation" or
  "guest network isolation") even on the same Wi-Fi — try a different
  network, or check your router's settings, if the above all check out.

**Connection refused**:
- The backend isn't running, or is running on a different port than the
  one in `API_BASE_URL`. Re-check both.
- A firewall on your computer may be blocking incoming connections on
  port 8000 — allow it, or temporarily disable the firewall to confirm.

**Cleartext HTTP blocked / "CLEARTEXT communication not permitted"**:
This shouldn't happen with this app as configured — cleartext traffic is
already enabled for local development in
`android/app/src/main/AndroidManifest.xml`
(`android:usesCleartextTraffic="true"`). If you see this error anyway,
confirm you rebuilt the app after any manifest changes (`flutter clean`
then rebuild), since Android caches manifest-derived settings per
install.

**Backend not running / crashes on startup**:
- Make sure you're in the `backend` venv (`source ../.venv/bin/activate`)
  and dependencies are installed (`pip install -r requirements.txt`).
- Check the terminal running uvicorn for a Python traceback.

**M-PESA Inbox shows "No phone SMS available"**:
- Expected on an emulator or a phone with no M-PESA messages -- this is
  the correct empty state, not an error (see "Demo Data vs. Phone SMS"
  above).
- On a phone that *does* have M-PESA messages: confirm you tapped **Grant
  SMS Permission** and chose "Allow" on the system dialog, then tap
  **Refresh**.

**SMS permission dialog says "send and view SMS messages"**:
- That's Android's fixed, generic wording for the whole SMS permission
  group -- it does not mean the app can send SMS. Only `READ_SMS` is
  declared in `AndroidManifest.xml`; Android only ever grants what's
  declared there, regardless of the dialog's wording.

**Permission permanently denied**:
- If you previously tapped "Don't allow" and checked "Don't ask again" (or
  denied twice), Android stops showing the prompt. The screen shows an
  **Open Settings** button instead -- tap it, then enable SMS permission
  manually under App info → Permissions.

**Phone cannot reach computer at all** (tried everything above):
- As a fallback, use the Android *emulator* instead of a physical phone —
  it doesn't need any network configuration:
  ```bash
  flutter emulators --launch <an_available_emulator_id>  # see: flutter emulators
  flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
  ```
  `10.0.2.2` is the emulator's special alias for your computer's
  `localhost` — it works even with the backend bound to `127.0.0.1`. This
  is also `API_BASE_URL`'s default if you omit `--dart-define` entirely,
  so `flutter run` with no arguments targets an emulator out of the box.

## Privacy: the M-PESA Inbox

The SMS inbox contains sensitive personal messages, so this feature is
built with a strict one-way boundary:

```
Phone SMS inbox
      ↓ (flutter_sms_inbox -- reads the existing inbox, once, on demand)
MpesaSmsParser (100% local, pure Dart, no platform/network calls)
      ↓ (only for messages the user explicitly selects)
Structured transaction candidate (code, sender, amount, phone, timestamp)
      ↓
POST /collections/{id}/transactions  (existing backend endpoint)
```

Concretely:

- Only `READ_SMS` is requested -- no `RECEIVE_SMS`, `SEND_SMS`, contacts,
  call log, location, camera, or microphone permissions.
- No live/background SMS listening: the inbox is read once when the
  screen opens or **Refresh** is tapped, never polled.
- The raw SMS body is never logged, never printed to debug output, and
  never sent anywhere -- `POST /collections/{id}/transactions` only ever
  receives the parsed fields (`raw_message` is left unset). The raw text
  is shown only in an on-device detail sheet (tap a message to see it).
- Messages that aren't M-PESA at all, or are M-PESA but not an incoming
  payment (airtime, withdrawals, balance checks, promotional, ...), are
  filtered out locally and never reach the rest of the app.
- The backend/agent (including Bedrock, in `AGENT_MODE=bedrock`) never
  sees SMS content -- only the same structured fields manual "Record
  Payment" entry already produces.

## Architecture

```
lib/
├── main.dart                 App entry point, theme, ApiService wiring
├── config/api_config.dart    API_BASE_URL (from --dart-define)
├── models/                   Plain Dart classes mirroring backend/app/models.py
│   └── mpesa_sms.dart        Local-only: a classified SMS (see Privacy above)
├── services/
│   ├── api_service.dart      One method per backend endpoint
│   ├── project_summary.dart  Aggregates a project's collections for display
│   ├── mpesa_sms_parser.dart Local M-PESA detector/parser (pure Dart, unit-tested)
│   └── sms_inbox_service.dart  Reads the device SMS inbox + permission state
├── theme/app_theme.dart      Material 3 theme, status colors
├── utils/format.dart         KSh formatting, dates
├── widgets/
│   ├── async_data_view.dart  Shared loading/error/retry wrapper
│   ├── status_badge.dart     Status chips (Confirmed/Pending/Needs review/...)
│   ├── progress_summary.dart Target/raised/remaining/progress bar block
│   ├── review_action_card.dart  The core "Credit X / Credit Y / Ignore" UI
│   └── whatsapp_sheet.dart   WhatsApp text bottom sheet + Copy
└── screens/
    ├── home/                 Project list
    ├── project/              Create project, project dashboard
    ├── collection/           Collection detail (Main or Harambee), create collection
    ├── contributors/         Contributor list + add
    ├── transactions/         Transaction list + record payment, reconciliation result
    ├── mpesa_inbox/          Browse existing phone SMS, select, import (see Privacy above)
    ├── review/                Persistent "needs review" screen
    └── report/               Contribution summary / Harambee summary
```

State management is intentionally simple: no external state management
package. Each screen owns its own data via `AsyncDataView` (a small
FutureBuilder wrapper with loading/error/retry built in) and reloads
explicitly after actions that change data. `ApiService` is a single
instance created in `main.dart` and threaded through screen constructors
(plus an `InheritedWidget` for the one reusable widget --
`ReviewActionCard` -- that's dropped into two different screens).

## Development

```bash
flutter pub get
flutter analyze
flutter test
```

No backend needed for `flutter analyze`/`flutter test` -- the tests mock
HTTP responses (`package:http/testing.dart`), so they run fully offline.
