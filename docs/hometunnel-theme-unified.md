# HomeTunnel unified theme fix — REQ-HT-001

## Scope and ownership

- Feed baseline `9730a0a`, isolated branch `fix/hometunnel-theme-unified`; theme read-only baseline `0bc8b5a1d25c203b47ba9068ef4723a3cc55e20c` (r13).
- Existing `wt-hometunnel-banner` was clean at baseline when discovered and remained clean at final regression. No files or commits in that worktree were changed.
- Application-only fix: `ui.js`, status/diagram/wizard banner DOM, wizard stepper classes. `settings.js` needs no modification: its native selects consume shared UI rules.
- No production writes, setting saves, tunnel operations, theme edits, package build, deployment, merge or push. The only browser access to the device was read-only resource URL inspection.

## Root cause and fix

The theme footer adds `.form-select` to settings controls. Generated palette CSS supplies its foreground and background-color, but the application owns an old dark background-image gradient. Dawn therefore mixes deep ink with a dark gradient rather than an owned pair. Domain select has the same application rule without the footer class. Explanation banners had inline deep backgrounds plus inherited text. Wizard pills hardcoded all three states; white on the active `#348cd4` is only **3.591:1**.

Shared `--ht-*` roles reference existing live `--bs-*` variables, with dark defaults when no theme is loaded. No computed-style snapshot, theme detection, palette-specific selector, style-attribute theme workaround or new theme tokens. Ink uses gray-700 (bright in the dark theme, deep in dawn), surface gray-200, raised surface gray-100. Brand primary and success are decorative border/icon roles. Active pills and apply/save/edit buttons invert the tested ink/surface pair instead of assuming white is readable on any brand fill.

Select rules own text, opaque background, background-image removal, border and focus together with higher specificity than the palette form-select rule. Native appearance is preserved. A separate 2px ink focus outline has >=3:1 computed contrast against the control surface; the original brand outline failed the default theme threshold and was independently RED→GREEN corrected.

All three information banners share stable `.ht-info-banner`/`.ht-info-icon` classes. Step bar, done/active/idle pills and arrows have stable classes; active has `aria-current=step`, decorative arrows/icons are hidden from accessibility. Arrow+pill grouping and wrapping remain intact. Existing shared alerts/labels/pre/button compatibility rules receive paired overrides, not a rewrite of every view. QR white backgrounds, SVG topology drawing colors, URL code chips and unrelated inline UI are intentionally unchanged. Alert state meaning remains in its existing text and semantic border; done retains its checkmark.

## Real browser TDD evidence

Actual Microsoft Edge headless, real application module source evaluated in browser, real pinned base/palette/ng CSS. Minimal LuCI form/view/uci/fs stubs are unavoidable; no copied production CSS or handwritten view renderers. The real settings render, wizard renderInner for all six positions, real step3 renderer, status and diagram unconfigured render paths are exercised. A safe example.org domain option is populated into the actual domain select to represent fetched state without calling zones or saving.

Vertical cycles observed:

| Slice | RED | GREEN |
|---|---:|---:|
| Select owned pair + focus presence | 61 failures initially (included one incidental border transition comparison, subsequently narrowed to stable pairs) | 60 checks, 0 failures |
| Wizard pills | 540 failing owned-pair checks | 540 checks, 0 failures |
| Information banners | 120 failing owned-pair checks | 120 checks, 0 failures |
| Existing shared roles | 171 failures / 195 checks | included in final suite |
| Focus non-text contrast | 3 default-palette failures | included in final suite |

Final suite: **5 palettes × (60 component samples × 3 phases + 3 select focus checks) = 915 checks, 0 failures**. Each palette includes 2 settings selects, 1 real domain select, 36 pills (6 positions × 6 labels), 8 rendered banners (6 wizard, status, diagram), 13 existing shared role fixtures. Six-position matrix covers reachable done/active/idle states; endpoints do not have impossible states. Before → opposite light/dark stylesheet → original is measured on the same DOM nodes. Returned ink/background/image pairs equal original pairs. Focus checks use actual DOM focus, not a CSS class. Borders are stored as evidence but transient theme border changes are not used for palette-revert equality.

The final 5-palette sample minimum text ratios are default 7.395, blackgold 13.890, canyon 12.872, luminousblue 14.636, luminousblue-light 12.194. No-theme fallback: **183 checks, 0 failures**. Existing wizard deployment tests **9/9**, diagram smoke **30/30**, and git diff whitespace validation passed.

**Boundaries:** this is true browser CSS/render TDD, not deployed-device acceptance. Native OS select popup option visuals are NOT certified by computed styles. Real theme menu/cache-enabled palette switching, keyboard Tab traversal, mouse-release focus retention, screen-reader behavior, disabled opacity composition, screenshots and broad unrelated UI hover/pressed states are not certified. Transparent/gradient RED samples fail the owned-pair contract; their raw RGB diagnostic ratio is not a WCAG-composited claim. Final pairs are opaque and directly measured.

## Repeat commands

From this worktree:

```sh
python luci-app-hometunnel/test/theme-browser-test.py --theme D:/DevPortal/homelede/luci-theme-infinityfreedom --out C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/hometunnel-unified-final2
python luci-app-hometunnel/test/theme-browser-test.py --theme D:/DevPortal/homelede/luci-theme-infinityfreedom --out C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/hometunnel-unified-unthemed --no-theme
node --test luci-app-hometunnel/test/test-wizard-deploy.cjs
node luci-app-hometunnel/test/test-diagram.mjs
git diff --check
```

Evidence directories under the active ta scratch path: `hometunnel-unified-red`, `hometunnel-unified-select-green3`, `hometunnel-unified-wizard-red`, `hometunnel-unified-wizard-green`, `hometunnel-unified-banner-red`, `hometunnel-unified-banner-green`, `hometunnel-unified-shared-red`, `hometunnel-unified-focus-red`, `hometunnel-unified-final2`, `hometunnel-unified-unthemed`. Each includes results/summary JSON and source/CSS SHA256 manifest; generated HTML contains safe fixture data only. Temporary evidence is not packaged.

## Loader cache / future authorized release

Read-only live settings inspection confirmed `L.env.resource_version = 26.268.60624~3e89467-1791937154`; both settings.js and ui.js requests carry that exact `?v=`. The live luci.js loader derives this value from its own script URL and applies it to every required class URL. It is a **LuCI-global resource key, not luci-app-hometunnel PKG_RELEASE**. Raising application release alone does not prove browser invalidation.

This source-only commit leaves `PKG_VERSION=1.0.0`, `PKG_RELEASE=1`. Future authorized package release must increment application release, build from the fixed commit, verify installed bytes and explicitly arrange reload/cache invalidation for the LuCI module URLs; test with cache enabled and actual theme menu light↔dark↔original. Do not add an unrelated theme cache bump or claim an app package upgrade automatically changes the LuCI-global key.

Deployable changed assets in that future package are:

- `/www/luci-static/resources/view/hometunnel/ui.js`
- `/www/luci-static/resources/view/hometunnel/status.js`
- `/www/luci-static/resources/view/hometunnel/diagram.js`
- `/www/luci-static/resources/view/hometunnel/wizard.js`

No settings source, backend executable, UCI config, credential or theme resource changes are required. Deploy only after separately authorized packaging/deployment and complete the device/native-popup acceptance boundaries above.
