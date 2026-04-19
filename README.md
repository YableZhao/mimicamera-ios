# Mimicamera

> A camera that sees the world in another photographer's colors.

Real-time photographic style transfer for iPhone. Pick a reference photo; the live viewfinder is recolored to match at 30 fps.

**Status:** Working prototype. Demoable in the iPhone 17 Pro simulator via XcodeGen-generated project.

## Shipped features

- **Six curated photographer looks** — Golden Hour, Overcast, Noir, Pastel, Film, Portrait — baked into the app bundle as 33³ `.cube` files with matching thumbnails.
- **Horizontal reference strip** — tap a thumbnail to apply its LUT instantly; the active look shows the photographic-red border.
- **Bring-your-own reference** — tap the Photos button to pick any photograph from your library; the iOS client uploads it to the backend, receives a fitted `.cube`, and applies it live.
- **Intensity slider** — interpolates in LUT space between identity and fitted LUT (not in pixel space). Haptic tick at α = 1.0.
- **Long-press A/B** — hold anywhere on the camera surface to flash back to the unstyled original; release to resume.
- **Dual-capture shutter** — tap to save both the unstyled original *and* the styled frame to Photos as separate assets.
- **Dark-mode chrome** — SF Pro Mono style chip, photographic-red accent, hidden status bar, portrait-locked.
- **Simulator test gradient** — a spectrum gradient is rendered through the current LUT on simulator so the full UI (chip, slider, A/B, shutter flash) can be exercised without camera hardware.

## How it works

1. You pick a reference photo — either from the curated strip or your Photos library.
2. For library refs, the image is posted to the [Mimicamera backend](https://github.com/YableZhao/mimicamera-api), which fits a 33³ 3D LUT using Pitié–Kokaram iterative distribution transfer in CIELAB with KDE-smoothed confidence weighting (a "low-rank confidence LUT" — a direct extension of the LoR-LUT research framing).
3. The `.cube` file is returned and applied live via `CoreImage.CIColorCube` at the preview frame rate.
4. The long-press A/B and intensity slider operate entirely on-device — no round-trips.
5. The shutter renders both the pre-LUT and post-LUT `CIImage` to JPEG and saves them via `PHPhotoLibrary`.

## Architecture

```
iPhone                              Fly.io / local
┌──────────────────┐   JPEG ref   ┌──────────────────┐
│ Mimicamera iOS   │ ───────────▶ │ mimicamera-api   │
│  AVFoundation    │              │  FastAPI         │
│  CoreImage       │ ◀─── .cube ──│  IDT + KDE       │
│  CIColorCube 30Hz│              │  + Claude curate │
└──────────────────┘              └──────────────────┘
```

Backend is stateless; the hot loop is entirely on-device.

## Running it

See [`SETUP.md`](SETUP.md) for the full walkthrough. In one breath:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Mimicamera.xcodeproj -scheme Mimicamera \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Run the backend separately if you want to hit `/fit_lut`:

```bash
cd ../mimicamera-api
source .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## Research

The LUT-fitting algorithm is a continuation of my research on LUT-based image processing:

- **LoR-LUT** — low-rank residual LUT learning (ECCV 2026 under review)
- [LUTor](https://github.com/YableZhao/LUTor) — web tool for histogram-based photo style transfer

The confidence-weighted regularization with KDE-smoothed coverage is a deliberate extension of the LoR-LUT low-rank framing — cells with high reference-density coverage get the full IDT transfer; low-density cells fall back toward identity to prevent posterization.

## Requirements

- iOS 17+
- iPhone 15 Pro or newer (recommended; the app runs on any iPhone but the LUT hot loop is tuned for A17 Pro)
- Xcode 15+

## Design

See [`design.md`](design.md) for the product and UX brief.

## Built with

- [Claude Code](https://claude.com/claude-code)

## License

MIT © 2026 Ziqi Zhao (Yable)
