# EchoIM iOS

## Prerequisites
- Xcode 26+
- iOS 17+ simulator or device
- Backend running at `http://localhost:3000`

## Run
Open `EchoIM.xcodeproj`, choose an available iOS simulator, then press `Cmd+R`.

To point at a different backend, set `EchoIMBaseURL` in `Info.plist`, for example:

```xml
<key>EchoIMBaseURL</key>
<string>http://192.168.1.10:3000</string>
```

## Test

```bash
xcodebuild -project EchoIM.xcodeproj -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' test
```

UI smoke tests require:
- backend running
- seeded account `smoke@test.local / password123`

## Status
P1 done: scaffold + login/register/home.

Later phases are tracked in `docs/superpowers/specs/2026-04-17-ios-app-design.md` section 8.
