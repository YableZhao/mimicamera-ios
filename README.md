# Mimicamera

> A camera that sees the world in another photographer's colors.

Real-time photographic style transfer for iPhone. Pick a reference photo; the live viewfinder is recolored to match at 30 fps.

**Status:** Prototype in development. Not yet on the App Store.

## How it works

1. You pick a reference photo (from Photos, or one of six curated photographer looks).
2. The image is sent to the [Mimicamera backend](https://github.com/YableZhao/mimicamera-api), which fits a 3D LUT using Pitié–Kokaram iterative distribution transfer in CIELAB with confidence-weighted regularization.
3. The `.cube` file is returned and applied live via `CoreImage.CIColorCube` on-device at 30 fps.
4. Intensity slider (blends in LUT space), long-press for A/B, shutter captures original + styled.

## Architecture

```
iPhone                              Fly.io
┌──────────────────┐   JPEG ref   ┌──────────────────┐
│ Mimicamera iOS   │ ───────────▶ │ mimicamera-api   │
│  AVFoundation    │              │  FastAPI         │
│  CoreImage       │ ◀─── .cube ──│  IDT + Claude    │
│  CIColorCube 30Hz│              │  curation        │
└──────────────────┘              └──────────────────┘
```

Backend is stateless. The hot loop is entirely on-device.

## Research

The LUT-fitting algorithm is a continuation of my research on LUT-based image processing:

- **LoR-LUT** — low-rank residual LUT learning (ECCV 2026 under review)
- [LUTor](https://github.com/YableZhao/LUTor) — web tool for histogram-based photo style transfer

The confidence-weighted regularization in the fitting pipeline is a direct extension of the LoR-LUT low-rank framing.

## Requirements

- iOS 17+
- iPhone 15 Pro or newer
- Xcode 15+

## Design

See [`design.md`](design.md) for the product and UX brief.

## Built with

- [Claude Code](https://claude.com/claude-code)

## License

MIT © 2026 Ziqi Zhao (Yable)
