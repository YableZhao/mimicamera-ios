# Mimicamera iOS — Claude Code Conventions

## Project

Real-time photographic style transfer camera for iPhone. SwiftUI + AVFoundation + CoreImage. Backend lives at [mimicamera-api](https://github.com/YableZhao/mimicamera-api).

## Code style

- SwiftUI first. UIKit only when a specific API requires it (e.g., camera UI surfacing).
- Prefer `@Observable` / `@State` / `@Environment` over `@StateObject` + `ObservableObject`.
- No third-party Swift packages unless strictly necessary. Prefer stdlib and Apple frameworks.
- Type annotations are encouraged where they aid clarity.
- English identifiers and comments.
- Comments: only for non-obvious WHY, not WHAT. No multi-line doc blocks.
- No emoji in code.
- SF Symbols for all iconography; never raster assets.

## Camera pipeline invariants

- Live LUT application runs on GPU via `CIColorCube`. No per-frame CPU work.
- `AVCaptureSession` auto-exposure is allowed, but white balance must be **locked** while a LUT is applied.
- Exposure EMA coefficient: **0.85** (tuned to not flicker on scene changes).
- LUT grid size: **33³**. Never 17³ (sky banding under motion).
- Intensity slider interpolates in LUT space, not pixel space. Re-upload `CIColorCube` on slider change; do not blend two rendered images.

## File organization

```
Mimicamera/
  App.swift
  Camera/        AVFoundation + CIColorCube live pipeline
  Reference/     PhotoKit picker, ref strip, style chip
  Capture/       Shutter, dual-write (original + styled)
  API/           URLSession wrapper for mimicamera-api
  Resources/
    CuratedLUTs/ *.cube baked looks
```

## Forbidden

- Face "beauty" filters.
- Any GenAI image generation in the app. Claude is used only for reference curation and style-name metadata.
- Watermarks on exports.
- Social share UI inside the app.

## Target

- iOS 17+, iPhone 15 Pro minimum.
- Portrait orientation only in v1.

## Research context

The LUT-fitting algorithm is a continuation of the author's research on LUT-based image processing (LoR-LUT, LUTor). When proposing algorithmic changes, preserve the research narrative — confidence-weighted LUT regularization is a deliberate extension of LoR-LUT's low-rank framing.
