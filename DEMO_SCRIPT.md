# Mimicamera — Interview demo script

30-minute Portfolio Walkthrough for Superpose's Founding iOS Engineer interview. Written to be a cue-card, not a rote recital — memorize the beats, not the words.

## Setup (day before)

- Charge your iPhone 15 Pro / 16 Pro / 17 Pro to 80%+.
- Build Mimicamera against the **device** (not simulator) via Xcode → ⌘R with your iPhone plugged in. Free-tier personal signing works; the provisioning profile is valid for 7 days.
- Ensure at least three distinct photographer reference photos are in your Photos library. Pick images with broad colour coverage — portraits, landscapes, scenes with sky + ground + skin tones all in-frame.
- Start `mimicamera-api` locally with your Mac's LAN IP reachable from the phone:
  ```bash
  cd mimicamera-api && source .venv/bin/activate
  uvicorn app.main:app --host 0.0.0.0 --port 8000
  ```
  Update the `apiBase` URL in `ContentView.swift` to your Mac's LAN IP (or run over USB tethering + localhost).
- Have a **laptop backup recording** of the full demo flow, in case signing expires mid-call or the network flakes.

## The 30 minutes

### Min 0–2 — Framing (don't skip this)

> *"Superpose's line is 'in the moment.' Mine is 'in the style.' I built a real-time style transfer camera for iOS — and the algorithm is my first-author research shipped as product."*

Two specific signals you're giving here:
1. You read their site carefully enough to echo their own framing.
2. Your research is on the exact thing they're building.

### Min 2–10 — Live demo (the hero)

Hand the phone to the interviewer, or hold it yourself aimed at something colourful in the room.

1. Open Mimicamera. The curated strip is already loaded (Golden Hour selected).
2. **Swap through the looks.** Tap Golden Hour → Overcast → Noir → Portrait. Each shift takes < 50 ms; the reference-strip border follows the selection.
3. **Drag the intensity slider** from 1.0 down to 0 and back up. Watch it glide through LUT space, not pixel space — the midway point is a coherent "weaker style," not a ghostly blend.
4. **Long-press the viewfinder.** Release. "That's the original. That's the styled."
5. **Tap the photo-picker button.** Choose one of your bring-your-own references. Chip flips to "Fitting colours…", then shows the Claude-generated style name. *"The backend is fitting a 33³ LUT from that one photo using Pitié–Kokaram distribution transfer — about 400 ms on a CPU."*
6. **Tap the shutter.** Toast: "Saved original + styled to Photos". Open Photos. Show both.

### Min 10–15 — Architecture whiteboard

Bring out a notebook or napkin. Draw:

```
iPhone                       Fly.io / local
┌─────────┐  reference JPEG   ┌──────────────┐
│ iOS app │ ────────────────▶ │ mimicamera   │
│  SwiftUI│                   │  -api        │
│  CoreImg│ ◀── 33³ .cube ── │  FastAPI     │
│  30Hz   │                   │  IDT + KDE   │
└─────────┘                   └──────────────┘
```

Explain:

- **On-device hot loop.** Every frame goes through a single `CIColorCube` filter, GPU-accelerated. No network per frame.
- **Backend is stateless and cheap.** CPU-only inference, 400 ms per fit, hashed /tmp cache by reference content.
- **The fallback ladder** (show `/fit_lut?mode=idt|hist|chroma`): L0 IDT target, L1 chroma-only light touch, L2 per-channel histogram matching. Each is a different trade of fidelity vs. speed.

### Min 15–20 — The research story

> *"This is my PhD direction shipped as a product. My paper LoR-LUT is a low-rank residual 3D LUT framework — I use it for image enhancement trained on paired data. The confidence-weighted LUT in this app is a direct extension: cells with high reference-coverage density get full IDT transfer, cells with low coverage fall back toward identity. That's how I keep the live viewfinder from posterizing when it ventures into colours the reference never showed."*

Beats to hit:
- **Research-to-product bridge.** Not many candidates can say "my algorithm is running in your pocket at 30 fps."
- **What the confidence map does.** Walk through one cell. "This cell is green. The reference has no greens. Confidence is zero. Output is identity green. No artefacts."
- **What you'd do with more time.** *"The classical IDT is a stopgap. The real product is the LoR-LUT neural predictor running on-device via CoreML — the fit becomes a sub-100 ms forward pass and the LUT adapts to scene content, not just reference distribution. That's my week-3 story."*

### Min 20–25 — The Claude Code workflow

Show the GitHub repos ([mimicamera-ios](https://github.com/YableZhao/mimicamera-ios), [mimicamera-api](https://github.com/YableZhao/mimicamera-api)).

- Scroll the commit list. Every commit has a `Co-Authored-By: Claude` trailer. Every message is tight and specific.
- Open one meaningful diff — `D5 iOS: PhotoKit reference picker + backend-wired fit flow` works well. Show the structured picker → URLSession multipart → Decodable response flow.
- Open `CLAUDE.md` in each repo. "These are the invariants I'm enforcing. 33³ grid, no PyTorch on backend, no face beauty filters, no watermarks. I refuse the agent when it drifts."
- Mention `project.yml` (XcodeGen). "Project config lives in git as readable YAML. Anyone cloning the repo types `xcodegen generate` and they have the same project I do."

### Min 25–30 — "What I'd do differently"

Don't hedge with fake-humility answers here. Pick a single strong technical observation.

> *"IDT is distribution-to-distribution and has no spatial awareness. For the scenes where the current version disappoints — a cluttered bookshelf, say — a classical 3D LUT can't fix local contrast. I'd add a small on-device CoreML model that predicts per-region tone curves from the reference and the scene jointly. That's a two-week ML project on top of the iOS work, and it closes the loop back to my research. In a separate direction, the Claude curation endpoint should learn from thumbs-up/down on each suggestion — a dataset from day one that teaches the curator what styles this particular photographer considers 'on brand' for them."*

Why this lands:
- It's honest about a limitation you actually understand.
- It proposes a concrete fix with a realistic timeline.
- It chains into your research direction rather than pivoting away from it.

## If things go wrong

- **App signing expired overnight.** Fall back to the simulator (gradient background; chrome still renders) or the laptop recording.
- **Network drops during a live fit.** Tap a curated look instead — those are bundled, no network needed.
- **Can't find a good reference in your Photos.** Have 2–3 pre-baked `.cube` files on the phone (the curated set already includes this).

## After the demo

- Thank them. Ask what they're most worried about in the next engineering hire.
- Follow up within 24 h with a one-paragraph recap of what you showed, a link to the repos, and a single pointed question. Not a resume. Not a list.
