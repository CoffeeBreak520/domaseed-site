# GEO-016 — Candidate accessibility and reading review

**Scope:** independent source-level review of the three unpublished files in `night-shift/drafts/site-candidate-20261128/`. This is not a review of the live homepage and does not imply publication.

**Method and limitation:** read each candidate HTML/CSS file and examined navigation/focus behavior exposed by markup and styles, heading and table structure, and responsive rules. A local browser executable was not available under the probed Chrome/Edge/Chromium command names. No real browser interaction, narrow viewport, or 200% zoom measurement was performed. Existing structure checks and prior Chrome renders were not counted as this task's viewport or keyboard tests.

## Findings

### 1. Repeated navigation has no skip link — all three pages

- **Location:** first content after `<body>`: `<main>` then the `nav[aria-label="Main navigation"]`, before each page header.
- **Issue:** none of the pages provides a skip-to-main-content link.
- **Impact:** keyboard and switch users must pass through the repeated navigation before reaching the page-specific content.
- **Recommendation:** place a first-focusable skip link before the navigation, target the main content with a stable `id`, and reveal the link on focus. Verify that focus lands at the intended content and remains visible.

### 2. Wide comparison table requires horizontal scrolling — two pages

- **Location:** `development/index.html`, section “What is confirmed, and what is still being developed?”; `parents/choosing-adventure-thinking-games/index.html`, shared `.table-wrap` CSS (the guide currently has no table).
- **Issue:** the development page table is wrapped in `.table-wrap { overflow-x: auto }`. The parent guide defines the same wrapper/table styles for future use but contains no table. On constrained widths the existing table can require horizontal scrolling.
- **Impact:** at narrow viewports or high zoom, readers may need two-dimensional navigation and can lose row/column context. Source inspection cannot determine whether the rendered table remains practical.
- **Recommendation:** test the development table at 320 CSS px and 200% zoom using keyboard and magnification. If scanning is difficult, consider a stacked presentation or provide an equally readable alternative that retains row/column context. Keep and verify the existing `scope="col"` and `scope="row"` header associations.

## Checks that look sound in source

- All pages have one `h1`, then section-level `h2` headings; homepage FAQ questions use `h3` under the FAQ section heading.
- The three pages use a labelled navigation landmark and native anchor links. Each defines a visible `:focus-visible` outline for links.
- The development comparison table has `thead`/`tbody`, column headers with `scope="col"`, and row headers with `scope="row"`.
- Homepage sections switch from a two-column grid to block layout below 700px. The two article pages reduce horizontal padding below 480px; the article table cells also reduce padding.

These are source observations only. The keyboard outline does not establish successful focus traversal, and responsive CSS does not establish usable rendering at any measured viewport or zoom.

## Result

**PARTIAL-MANUAL.** The source-level review and actionable findings are complete. Actual keyboard, narrow-screen and 200% zoom checks remain unmeasured because no browser executable was available. No candidate or live site files were modified.

Evidence: `night-shift/evidence/20261128-GEO-016-accessibility-review.json`.
