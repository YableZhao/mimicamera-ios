# Setting up the Xcode project

The Swift sources under `Mimicamera/` are ready to drop into a fresh Xcode project. Follow these steps once Xcode is installed.

## 1. Create the Xcode project

1. Open Xcode → **File → New → Project…**
2. Choose **iOS → App** → Next.
3. Product Name: `Mimicamera`
   Organization Identifier: `com.yablezhao` (or your own)
   Interface: **SwiftUI**
   Language: **Swift**
   Storage: **None** (no Core Data)
   **Uncheck** "Include Tests" (add them later if needed)
4. When prompted for the location, pick this repository's root (`mimicamera-ios/`). Xcode will create a nested `Mimicamera/` directory — **delete** the nested `Mimicamera/Mimicamera/` folder Xcode just generated (it will include a boilerplate `MimicameraApp.swift` and `ContentView.swift` that conflict with ours).
5. In Xcode's project navigator: **right-click → Add Files to "Mimicamera"…** and select `Mimicamera/` (this repo's hand-written source tree). Uncheck "Copy items if needed"; select the **Mimicamera target**; choose "Create groups".

## 2. Project settings

In the project settings:

- **General** tab, Deployment Info:
  - iOS Deployment Target: **17.0**
  - Device Orientation: **Portrait** only
  - Status Bar Style: **Dark Content** (or Hidden — it is hidden in code)
- **Info** tab: replace the auto-generated Info values with the entries from our `Mimicamera/Info.plist` (or add `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription` manually).
- **Signing & Capabilities**: use your free Apple ID for personal team signing. No paid developer program required.

## 3. First build

- Choose a simulator (e.g. iPhone 15 Pro) or a connected device.
- Build and run. The camera preview will be black in the simulator (no camera); on a device, you will see the live feed.

## 4. Hooking up the backend

The `MimicameraClient` in `Mimicamera/API/MimicameraClient.swift` expects a running `mimicamera-api`. During development, run the backend locally:

```bash
cd ../mimicamera-api
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Point the iOS app at `http://<your-mac-ip>:8000` when testing on a physical device. For the simulator, `http://127.0.0.1:8000` works.

## Source tree overview

```
Mimicamera/
  MimicameraApp.swift       App entry point (SwiftUI @main)
  ContentView.swift         Root view — camera + top bar + shutter row
  Info.plist                Permissions + orientation + dark mode
  Camera/
    CubeLUT.swift           .cube parser + CIColorCube builder + LUT blend
    LUTPipeline.swift       AVCaptureSession + CoreImage + state
    CameraView.swift        MTKView-backed Metal preview surface
  API/
    MimicameraClient.swift  URLSession client for /fit_lut
```

## Known deferred work

These are intentionally not in the initial scaffold:

- `Reference/ReferenceStrip.swift` — bottom thumbnail picker (D5).
- `Reference/ReferencePicker.swift` — PhotoKit multi-select (D5).
- `Capture/ShutterButton.swift` + `CaptureWriter.swift` — dual save original + styled (D6).
- `Resources/CuratedLUTs/*.cube` — six baked photographer looks (D9).

See the plan file (`~/.claude/plans/interview-process-founding-ios-agile-cocoa.md`) for the full 2-week schedule.
