# Mimicamera — Design Brief

## Product principle

*Photographer-first, chrome-last.* The camera is the entire screen. Every UI element earns its pixels. Respect the craft — no filter-app-style overlays, no "enhance" AI spam, no beautification.

## Visual system

- **Theme.** Dark by default (camera apps always are). Matte black `#0B0B0C` panels; never pure `#000`.
- **Accent.** Photographic red `#D14A3A` for shutter and active states. Single accent; everything else neutral.
- **Typography.** SF Pro Text for UI; SF Mono for numeric metadata (focal length, intensity %).
- **Iconography.** SF Symbols only; never raster.
- **Radius and spacing.** 8-point grid. 16pt radius on cards, 24pt on modals.

## Layout (portrait)

```
┌─────────────────────────────┐
│  ● REC    Moody Editorial   │ ← top bar: status dot, style name chip
│                             │
│                             │
│     [full-bleed camera]     │
│                             │
│                             │
│       ━━━━━●━━━━━           │ ← intensity slider (floating, semi-transparent)
│                             │
├─────────────────────────────┤
│  [ref1][ref2][ref3] [+]  ◉  │ ← bottom: horizontal ref strip + shutter
└─────────────────────────────┘
```

## Interaction patterns

- **Tap ref thumb** → select; crossfade LUT (250 ms).
- **Drag intensity slider** → live LUT-blend; haptic tick at α = 1.0.
- **Long-press viewfinder** → show original under finger; release to resume styled.
- **Tap shutter** → capture both original and styled; haptic + shutter sound.
- **Tap [+] on ref strip** → PhotoKit picker (multi-select for curation mode).
- **Pinch viewfinder** → zoom (AVCaptureSession only; LUT is scale-invariant).
- **Double-tap background** → swap last two references.

## Motion

- LUT crossfade: 250 ms ease-out. Never jarring.
- No bouncy or spring animations; this is a professional-feeling app.
- Shutter: iris-style radial collapse, 120 ms.

## States

- **No reference selected.** Six curated photographer thumbs in the strip; no slider; CTA chip *"Pick a look."*
- **Reference selected, LUT baking.** Ghost slider + skeleton style chip. Microcopy: *"Reading the style…"* (Claude curation) or *"Fitting colors…"* (IDT bake).
- **Fitting error.** Inline toast at top with a `Retry` action; revert to previous LUT or identity.
- **Hero-shot captured.** Brief flash; thumbnail slides into the ref-strip origin (iMessage-send style).

## Accessibility

- VoiceOver labels on every ref thumb. Claude-generated style description is the default label.
- Reduced motion: crossfade becomes hard cut; no pinch animation.
- Dynamic Type applies to metadata only; main layout is fixed.

## Anti-patterns (explicitly banned)

- Face "beauty" filters.
- Watermarks on exports.
- Social share sheets inside the app.
- Any GenAI content generation beyond the Claude style description.

## Color tokens (for future implementation)

| Token | Hex | Use |
|---|---|---|
| `bg.base` | `#0B0B0C` | Top/bottom bar surfaces |
| `bg.card` | `#141416` | Ref strip cards |
| `bg.overlay` | `#00000080` | Slider track base |
| `fg.primary` | `#F5F5F7` | Text, SF Symbols |
| `fg.secondary` | `#8E8E93` | Disabled, placeholder |
| `accent.shutter` | `#D14A3A` | Shutter, active ref outline |
| `accent.shutter.pressed` | `#A83A2E` | Shutter pressed |
