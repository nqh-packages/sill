---
id: floating-chrome-clears-keyboard
kind: code
severity: unbreakable
globs:
  - "iOSClient/StreamScreen.swift"
  - "iOSClient/PadWorkspaceChrome.swift"
  - "iOSClient/TactileTrackpadDeck.swift"
threshold: 0.7
provider: subq
localize: true
fix: "Take the bottom margin of floating chrome (the dock capsule, its orb, the floating trackpad) from StreamWorkspaceState.chromeBottomClearance(containerWidth:safeBottom:keyboardOcclusion:), passing the live keyboard occlusion, so it rests above the software keyboard and its key row."
---

## Question

Does this Swift file compute the bottom margin, bottom inset or bottom avoidance of floating chrome (a floating capsule, dock, palette, orb or floating trackpad positioned with `.position` or an avoidance `EdgeInsets`) from only the safe-area bottom inset and a constant, such as `max(22, insets.bottom)` or `max(containerWidth >= 600 ? 22 : 14, insets.bottom)`, without calling `StreamWorkspaceState.chromeBottomClearance` with a keyboard occlusion?
Exclude the body of `chromeBottomClearance` itself, and exclude top or side margins.
If no candidate clearly qualifies, answer no.

## Bad

```swift
struct PadFloatingCapsule: View {
    let containerSize: CGSize
    let insets: FullScreenPolicy.Insets

    private var bottomMargin: CGFloat {
        max(containerSize.width >= 600 ? 22 : 14, insets.bottom)
    }

    private var restingCenter: CGPoint {
        CGPoint(x: containerSize.width - 36, y: containerSize.height - bottomMargin - 24)
    }
}
```

## Good

```swift
struct PadFloatingCapsule: View {
    let containerSize: CGSize
    let insets: FullScreenPolicy.Insets
    var keyboardOcclusion: CGFloat = 0

    private var bottomMargin: CGFloat {
        CGFloat(StreamWorkspaceState.chromeBottomClearance(
            containerWidth: Double(containerSize.width),
            safeBottom: Double(insets.bottom),
            keyboardOcclusion: Double(keyboardOcclusion)
        ))
    }
}
```
