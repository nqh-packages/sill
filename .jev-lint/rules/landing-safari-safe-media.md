---
id: landing-safari-safe-media
kind: code
severity: unbreakable
globs:
  - "landing/src/**/*.astro"
threshold: 0.7
localize: true
fix: "Remove CSS filter: drop-shadow(...) (crashes iOS Safari WebKit on large device bezels/videos) and ensure every <img> and <video> declares explicit width and height attributes."
---

## Question

Does this Astro file either use CSS `filter: drop-shadow(...)` OR render an `<img>` or `<video>` element that is missing explicit `width` or `height` HTML attributes?
Exclude `box-shadow` (which is safe) and exclude `<link>` or `<meta>` tags.
If no candidate clearly qualifies, answer no.

## Bad

```astro
<div class="device">
  <img src="/shots/phone-orb.jpg" alt="Phone orb" />
</div>
<style>
  .device { filter: drop-shadow(0 24px 48px rgba(0, 0, 0, 0.7)); }
</style>
```

## Good

```astro
<div class="device">
  <img src="/shots/phone-orb.jpg" width="620" height="1348" alt="Phone orb" />
</div>
<style>
  .device { box-shadow: 0 24px 48px rgba(0, 0, 0, 0.45); }
</style>
```
