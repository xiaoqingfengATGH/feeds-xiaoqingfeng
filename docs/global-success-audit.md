# Global success ownership regression

- Base: `7630b31`; branch: `fix/palette-global-emerald-app`.
- Removed four Internet-only luminous palette overrides from overview.css. Healthy Internet and generic KPI text/dots now consume the same theme-owned success colors. Warning/fault/unknown rules, data collection, state classification and polling are unchanged.
- Application fallback CSS cache key is v6; coordinated theme footer preloads CSS v6 and JS v3. Theme palette entry points use v22.
- Final full `node --test tests/*.test.cjs`: **27 passed, 0 failed, 0 skipped**. Evidence: `docs/global-app-green.log`. Real Edge test confirms healthy Internet and generic KPI equality across palettes, and unchanged warning/fault/unknown semantics.
- `global-cache-red.log` is retained as historical RED evidence, not the final regression result.
- Theme-side fixed-base Edge audit: 792 identical unique cases before/after, 184 failures → 0; separate neutral/sidebar ownership matrix 104 cases, 0 → 0. Disabled cases are opacity behavior checks, not WCAG contrast claims.
- Complete report and raw artifacts: companion theme worktree `D:/DevPortal/homelede/wt-palette-global-emerald-theme/luci-theme-infinityfreedom-ng/docs/audit.md`, `palette-summary.json`, `palette-audit-{before,after}.json`, `palette-owners-{before,after}.json`.
- No deployment, package install, push, merge or PR performed. Independent review and device-side verification remain outside this local commit task.
