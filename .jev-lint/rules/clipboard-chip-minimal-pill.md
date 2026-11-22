---
id: clipboard-chip-minimal-pill
kind: code
severity: unbreakable
globs:
  - "iOSClient/ClipboardChip.swift"
threshold: 0.7
localize: true
fix: "Keep ClipboardChip's active chip minimal: only ClipboardPasteButton and the circular dismiss button inside TactileGlassGroup, with no extra title/subtitle card text."
---

## Question

Does the active `chip` view in `ClipboardChip` render visible `Text(...)` title/subtitle copy or a multi-line card layout alongside `ClipboardPasteButton`, instead of keeping the active chip to only the Paste button and circular dismiss button?
Exclude `noteView` (which shows brief post-paste confirmation) and exclude `.accessibilityLabel` / `.accessibilityHint` strings.
If no candidate clearly qualifies, answer no.

## Bad

```swift
private var chip: some View {
    HStack {
        VStack(alignment: .leading) {
            Text("Paste on Mac")
            Text("Where the cursor is.")
        }
        ClipboardPasteButton(client: client)
        dismissButton
    }
}
```

## Good

```swift
private var chip: some View {
    TactileGlassGroup(spacing: 6) {
        HStack(spacing: 6) {
            ClipboardPasteButton(client: client)
                .controlSize(.small)
            dismissButton
        }
    }
}
```
