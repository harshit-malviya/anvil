# Anvil — Build & Distribution Setup

## 1. Scaffold the project

```
flutter create --org com.anvil --platforms windows,android anvil
cd anvil
flutter config --enable-windows-desktop
```

Add dependencies to `pubspec.yaml`:

```yaml
dependencies:
  flutter_riverpod: ^2.5.0
  go_router: ^14.0.0
  syncfusion_flutter_pdf: ^26.0.0
  image: ^4.2.0
  file_picker: ^8.0.0
  path_provider: ^2.1.0
  share_plus: ^9.0.0
  shared_preferences: ^2.2.0
  google_fonts: ^6.2.0   # for Space Grotesk / Inter / IBM Plex Mono

dev_dependencies:
  flutter_lints: ^4.0.0
  mocktail: ^1.0.0        # for controller unit tests
```

Run `flutter pub get` after adding.

## 2. Windows build

```
flutter build windows --release
```

Output binary lands in `build/windows/x64/runner/Release/`.

To build the Windows installer (`AnvilSetup-1.0.0.exe`), use Inno Setup:
```powershell
iscc windows/installer/anvil.iss
```
The compiled installer will be created at `build/windows/installer/AnvilSetup-1.0.0.exe`.
The installer includes custom setup icon, Start Menu / Desktop shortcuts with app icon, and Windows Add/Remove Programs icon integration.

## 3. Android build

```
flutter build apk --release
```

For v1, a self-signed release APK is fine for GitHub distribution (sideloading). Generate a
keystore and configure signing in `android/app/build.gradle` per standard Flutter docs — don't
commit the keystore file to the repo; document the signing step in `README.md` instead so anyone
building from source can generate their own.

## 4. GitHub Actions CI (auto-build on release tag)

Create `.github/workflows/release.yml`:

```yaml
name: Build Release
on:
  push:
    tags:
      - 'v*'

jobs:
  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: flutter build windows --release
      - uses: actions/upload-artifact@v4
        with:
          name: anvil-windows
          path: build/windows/x64/runner/Release/

  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: anvil-android
          path: build/app/outputs/flutter-apk/app-release.apk
```

Attach both artifacts to the GitHub Release manually the first time; automate with
`softprops/action-gh-release` once the workflow is confirmed working.

## 5. Landing page

GitHub Pages, single static page: app name, one-line pitch, screenshots, two download buttons
(Windows / Android) pointing at the latest GitHub Release assets. No build tooling needed — plain
HTML is fine, don't over-engineer this.

## 6. README.md (repo root) must include

- What the app does, in one paragraph
- Screenshots (add once v1 UI exists)
- Download links
- "Build from source" instructions (the two `flutter build` commands above)
- License (recommend MIT or GPLv3 — flag this choice back to the human, don't assume)
