# Native Editor Fonts

All native editor text uses the vendored Inter 4.1 Regular desktop font:

```text
Inter-Regular.ttf
SHA-256: 40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82
```

The native Dear ImGui shell uses the vendored Font Awesome Free 7.2.0 Solid
desktop font only for icon glyphs:

```text
fa-solid-900.otf
SHA-256: c1091147299a846195bbca8b26528de6c9af842f236e7db44a1c2e8c9df52372
```

The font is loaded as a dedicated ImGui font atlas entry. It is a UI display
asset only and has no authority over playback, rendering, timeline truth, or
`FinalFrameSurface`.

The upstream license is preserved at:

```text
apps/imgui/third_party/inter/LICENSE.txt
apps/imgui/third_party/font-awesome/LICENSE.txt
```

Upstream:

```text
https://github.com/FortAwesome/Font-Awesome/releases/tag/7.2.0
https://github.com/rsms/inter/releases/tag/v4.1
```
