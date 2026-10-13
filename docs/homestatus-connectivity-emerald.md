# Internet connectivity emerald hotpatch

## Scope and ownership

Approved healthy Internet KPI only: `body[data-if-palette="luminousblue"] .ngov-kpi.ngov-kpi-internet .ngov-kpi-v.state.g` uses `#70d6b0`; light sibling uses `#16724f`. Same-card `.ngov-dot.g` uses the same palette color. Existing weight 600 retained. App owns the dedicated class and four precise CSS rules; no text-matching selectors, inline semantic colors, global success change, glow, gradient or badge. Reachability logic/data/actions are untouched. Warning/red/muted and blackgold/canyon remain baseline-owned.

Theme change is only footer JS cache key v1→v2; JS upgrades the existing CSS preload to v5. Palette files/generator/header/login and palette v21 unchanged. No SDK/IPK, opkg changes, merge, push or PR.

## Verification

- DOM RED: missing dedicated Internet class, then GREEN.
- CSS RED: original baseline computed `rgb(140, 146, 84)` rather than emerald. Real isolated Edge reproduced the same failure against baseline CSS using `HOMESTATUS_CONNECTIVITY_BASELINE=1`.
- Final suite: original 24 plus 2 connectivity tests = 26/26 PASS. Real Edge tests load actual app CSS followed by generated palette CSS, cover both luminous palettes, blackgold/canyon and unchanged warning/red/muted state colors.
- Palette generator `--check` with explicit updated `HOMESTATUS_OVERVIEW_CSS` passes without modifying generated palettes.
- jsdom is used for the actual renderer and polling. Its computed style specificity disagreed with Chromium, so palette cascade assertions use real Edge (not a CSS workaround).
- Final live dashboard after cache-reload: CSS v5, JS v2, palette v21; healthy text/dot `rgb(112, 214, 176)`, weight 600, no theme fallback.
- Live DOM-only temporary light palette href/body switch: text/dot `rgb(22, 114, 79)`, weight 600 on `rgb(237, 241, 254)`; restored luminousblue after checking. No UCI palette write.

Re-run from app directory with `HOMESTATUS_THEME=D:/DevPortal/homelede/wt-homestatus-connectivity-theme/luci-theme-infinityfreedom-ng` and `HOMESTATUS_PLAYWRIGHT=C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/homestatus-layout/node_modules/playwright`, then `npm test`. Playwright is an existing isolated scratch installation, not a runtime package dependency.

## Deployment and recovery

Exact originals backed up to `/root/homestatus-hotpatch-connectivity-20261014-003409` before uploading staged files. Staged footer compiled using real router `ucode -S` and `loadfile(...,{raw_mode:false})` before publication. All installed files chmod 644; remote hashes match source. JS/CSS HTTP GET returned 200 and exact matching SHA256.

| Target | SHA256 |
| --- | --- |
| `/www/luci-static/resources/view/homestatus/overview.css` | `8eec1d724a3814150ebec6f5a68f7f6a8da693d8ef14811a7fe8f7a3dfa5b926` |
| `/www/luci-static/resources/view/homestatus/overview.js` | `0d391ce52356eb4fdc1c0be3746a161c7283462f3f8388e03b482599d90436ef` |
| `/usr/share/ucode/luci/template/themes/infinityfreedom-ng/footer.ut` | `445a8bab7a5a0f20f81da8003840215309f87171572ee2f97746a871ec89a0f3` |

Before/after `/etc/config/infinityfreedom-ng` SHA256 `ffc3cac919b1885e449d0d21c9bd1d580f98f230ddd04a7aee1df8a5e6ef8d64`; `/etc/config/luci` `9862bd66b13ef02bb7096d82c8436b6e2a069445b20c2ab76a1eb0f8fb600654`; palette remains `luminousblue`.

Rollback only those three paths from the named backup, chmod 644, then force reload HTML and resources. Do not change configuration or install packages.

To repeat a nonpersistent light check in browser session `homestatus-live-check`: save current palette link href and body `data-if-palette`, swap link filename `palette-luminousblue.min.css` to `palette-luminousblue-light.min.css`, await load, set body attribute to `luminousblue-light`, read `.ngov-kpi-internet .state` and `.ngov-dot`; restore both in a `finally` block. Never call UCI save.
