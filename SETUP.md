# Setting up and running Mimicamera

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). You do not need to create a project manually — open the generated `Mimicamera.xcodeproj` and press ⌘R.

## First-time setup

```bash
brew install xcodegen           # one-time, if you do not have it
cd mimicamera-ios
xcodegen generate               # (re)creates Mimicamera.xcodeproj from project.yml
open Mimicamera.xcodeproj       # opens in Xcode
```

## Build and run

From the command line (headless):

```bash
xcodebuild \
  -project Mimicamera.xcodeproj \
  -scheme Mimicamera \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  build
```

Or in Xcode: pick a simulator destination (iPhone 17 Pro is recommended) and hit ⌘R.

The simulator will not show a live camera feed (simulator has no camera). You will see the dark-mode UI chrome — the style chip at the top and the shutter button at the bottom. On a physical iPhone you will see the live feed behind them.

## Install and launch on a booted simulator

```bash
xcrun simctl boot "iPhone 17 Pro"               # if not already booted
open -a Simulator                                # brings Simulator app to front

xcodebuild ... build                             # as above

APP=$(find ~/Library/Developer/Xcode/DerivedData -name Mimicamera.app -path '*iphonesimulator*' | head -1)
xcrun simctl install booted "$APP"
xcrun simctl privacy booted grant camera com.yablezhao.mimicamera
xcrun simctl launch booted com.yablezhao.mimicamera
```

## Hooking up the backend

The `MimicameraClient` in `Mimicamera/API/MimicameraClient.swift` expects a running `mimicamera-api`. Run the backend locally:

```bash
cd ../mimicamera-api
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Point the iOS app at `http://<your-mac-ip>:8000` when testing on a physical device. For the simulator, `http://127.0.0.1:8000` works.

## Source tree

```
mimicamera-ios/
  project.yml                   XcodeGen configuration — the source of truth
  Mimicamera.xcodeproj/         Generated; commit for CI convenience
  Mimicamera/
    MimicameraApp.swift         SwiftUI @main entry
    ContentView.swift           Camera surface + top chip + shutter row
    Info.plist                  Permissions + orientation + dark mode
    Camera/
      CubeLUT.swift             .cube parser + CIColorCube builder + blend
      LUTPipeline.swift         AVCaptureSession + CoreImage + state
      CameraView.swift          MTKView-backed Metal preview
    API/
      MimicameraClient.swift    URLSession client for /fit_lut
    Resources/
      CuratedLUTs/
        demo-warm.cube          Baked offline for D2 testing
        demo-cool.cube
```

## Deferred work (per the plan)

- `Reference/ReferenceStrip.swift` — bottom thumbnail picker (D5)
- `Reference/ReferencePicker.swift` — PhotoKit multi-select (D5)
- `Capture/ShutterButton.swift` + `CaptureWriter.swift` — dual save (D6)
- More curated `.cube` files — six real photographer looks (D9)

Full plan: `~/.claude/plans/interview-process-founding-ios-agile-cocoa.md`.
