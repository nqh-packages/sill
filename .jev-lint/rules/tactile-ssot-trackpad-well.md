---
id: tactile-ssot-trackpad-well
kind: code
severity: unbreakable
globs:
  - "iOSClient/StreamScreen.swift"
  - "iOSClient/TactileTrackpadDeck.swift"
  - "iOSClient/PadWorkspaceChrome.swift"
  - "iOSClient/ControlCenterSheet.swift"
threshold: 0.7
provider: subq
localize: true
fix: "Render trackpad surfaces through TactileTrackpadWell (SSOT in TactileTrackpadDeck.swift) instead of wrapping TrackpadView directly with ad-hoc backgrounds, captions, or borders."
---

## Question

Does this Swift file instantiate `TrackpadView` directly outside `TactileTrackpadWell` to build a custom trackpad surface with its own background, border, corner radius, or caption instead of reusing `TactileTrackpadWell`?
Exclude the implementation of `TactileTrackpadWell` itself (`struct TactileTrackpadWell: View`) and exclude `InputOverlay` or non-trackpad views.
If no candidate clearly qualifies, answer no.

## Bad

```swift
private var naturalPad: some View {
    ZStack {
        RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.6))
        TrackpadView(client: client)
        Text("Trackpad").font(.caption)
    }
}
```

## Good

```swift
private var naturalPad: some View {
    TactileTrackpadWell(
        client: client,
        placement: .natural(bottomInset: insets.bottom)
    )
}
```
