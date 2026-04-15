# Design: What's New UI

**Date:** 2026-04-15
**Status:** Draft
**Data layer:** `_spec/designs/260415_WhatsNewData.md` (implemented)

---

## Goal

Surface vault changes since a visitor's last visit without adding a dedicated
"What's New" route. Changes should be discoverable in-context — at the tree
sidebar, at the top of each changed document, and inside the document body
itself via margin change bars. A single mark-as-read action clears all
indicators at once.

## Non-goals

- A `/whats-new` destination page or route.
- Intra-line word-level diff highlighting. (Line-level margin bars only.)
- Per-document or fine-grained acknowledgement. Mark-as-read is whole-vault.
- Any notification outside the app (email, push, etc.).

## User stories

1. As a returning visitor, when I load any page, I see a dismissible toast
   telling me how many docs changed since my last visit.
2. As a visitor browsing the tree, I can see at a glance which files in the
   sidebar have changed since my last visit.
3. As a visitor opening a changed document, I see a banner at the top
   identifying who changed it and when, with a "Mark as read" action.
4. As a visitor reading a changed document, I can see exactly which lines are
   new or modified via colored bars in the left margin of the rendered page.
5. As a visitor, one click on "Mark as read" — from the toast, the banner,
   anywhere — advances my cookie to current HEAD and clears every indicator.

## Surfaces

### 1. Global toast (on every page load with changes)

- Shown once per page load when `@whats_new.kind == :diff`.
- Desktop: `toast toast-top toast-end` (daisyUI). Mobile: `toast toast-bottom
  toast-center`. Breakpoint at `sm`.
- Content: "**5 pages changed** since {relative(from_date)}" + two actions:
  "Dismiss" (closes for this page load only, cookie untouched) and
  "Mark as read" (advances cookie, clears all indicators).
- Auto-dismiss: none. User must act or navigate. A LiveView-managed
  `phx-click="dismiss_whats_new_toast"` sets a transient assign so the toast
  does not re-appear during the current LiveView session; a page reload will
  show it again until the user marks as read.
- `kind: :empty` and `kind: :no_baseline` → no toast.

### 2. Sidebar change indicator

- Each `<.tree_node>` whose `path` is in `@whats_new.files` renders a small
  colored dot to the right of the file name:
  - green = `:added`
  - blue = `:modified`
  - amber = `:renamed` (tooltip: "Renamed from {previous_path}")
  - gray = `:deleted` (the node still renders briefly if it was present at
    cookie baseline but not at HEAD — but the current tree only shows files
    that exist at HEAD, so in practice `:deleted` entries never appear in the
    sidebar. They are reachable only from the toast count.)
- Folder nodes containing any changed descendant get a faint dot too, so
  users can see where to drill in without expanding every folder.
- Implementation: build a `MapSet` of changed paths from `@whats_new.files`
  once per render; pass down to the tree component; each node checks
  membership. O(n) in tree size, negligible.

### 3. Per-document banner (top of doc view)

- Rendered at the top of `VaultLive` / the doc route when the currently
  viewed `path` is in `@whats_new.files`:

  > **Changed since your last visit** — {author}, {relative(last_commit_date)}
  > [Mark as read]

- Uses `<.icon name="hero-sparkles">` on the left, a subtle tinted background
  (`bg-info/10 border-info/30`), rounded. Dismiss via "Mark as read" only —
  no per-doc dismiss, since that would desync from the sidebar dots.
- For `:renamed` files, the banner notes the rename:
  "Renamed from `{previous_path}` and updated — {author}, {date}".

### 4. Inline line-level change bars

- Rendered inside the markdown body as a 3px left-border on each changed
  line block:
  - green bar = added lines
  - blue bar = modified lines
- No red deleted markers inside the body (deleted content is gone; deleted
  *files* already surface via the toast count).
- No intra-line word highlighting in v1. A whole modified line gets a blue
  bar regardless of how much of it changed. This matches Neovim's gitsigns.
- Baseline for the diff is `summary.from_commit` (the cookie baseline), not
  the previous commit. So a visitor who hasn't come back in a week sees
  everything since *their* last visit, not since the latest commit.

## Data additions required

The existing data layer provides everything for surfaces 1–3. Surface 4
(margin bars) requires per-line diff information that `Docpub.WhatsNew.Git`
does not currently emit. Add:

- `Docpub.WhatsNew.Git.hunks(repo_path, from_sha, to_sha, file_path)` →
  `{:ok, [%Hunk{start_line: int, line_count: int, kind: :added | :modified}]}`.
  Uses `git diff --unified=0 from..to -- file_path` and parses `@@` headers;
  returns line ranges in the **new** file.
- `Docpub.WhatsNew.Summary` gains no new fields — hunks are fetched lazily
  only for the currently viewed document, via a new cache entry keyed by
  `{from_sha, to_sha, path}`. Most visits view 1–3 docs; caching per-doc
  keeps the cost bounded.
- New public helper `Docpub.WhatsNew.hunks_for(path)` that the LiveView
  calls when rendering a changed doc.

### Difficulty of hunk-level highlighting

Not very difficult. Concretely:

- `git diff --unified=0` output is well-defined; hunk headers look like
  `@@ -12,0 +13,4 @@` (old-start, old-count, new-start, new-count). Parsing
  is a ~20-line regex + reducer.
- Mapping hunks to rendered HTML lines is the trickier part. Our Markdown
  renderer produces arbitrary HTML, so "line 13 of the source" does not
  cleanly map to "the third `<p>` in the output." Two options:
  1. **Source-line data attributes.** Extend the markdown renderer to emit
     `data-source-line="N"` on each top-level block. Then a small hook
     (`ChangeBars`) walks the DOM on mount, cross-references the hunk list,
     and adds a `.changed-added` / `.changed-modified` class to each block
     whose source-line range intersects a hunk.
  2. **Pre-render annotation.** Compute which source lines are changed
     server-side and pass them to the renderer, which wraps affected blocks
     in a marker. More coupling but no client JS.
- Recommend option 1: it keeps the renderer simple and moves the mapping to
  a reusable hook. The hook is ~30 lines of JS.

## Interactions

### Mark-as-read flow

- All three "Mark as read" affordances (toast, banner, possible header
  button) POST to a new route: `POST /whats-new/mark_read` →
  `WhatsNewController.mark_read/2`. The controller calls
  `Docpub.WhatsNew.Cookie.encode/1` with `last_git_commit` set to the
  current HEAD and `last_visit_date` set to now, writes the cookie, and
  redirects back to `conn.request_path || "/"`.
- In LiveView, the button uses a `<.link>` with `method="post"` rather than
  a LV event, since cookies can only be stamped on a regular HTTP response.
  After the redirect, the assign repopulates with `:empty` or `:no_baseline`
  and all indicators disappear.

### First visit (`:no_baseline`)

- No toast, no banner, no dots. The data layer has already stamped a fresh
  cookie, so the *next* visit has a real baseline. This is intentionally
  silent — no "welcome" affordance in v1.

### Empty state (`:empty`)

- No toast, no banner, no dots. Nothing to show; don't draw attention to
  nothing.

## Accessibility

- Colored dots/bars pair with `title`/`aria-label` text ("Added", "Modified")
  so colorblind users and screen readers get the same signal.
- Toast is `role="status"` + `aria-live="polite"`; the "Mark as read" action
  is a real `<button>` inside a form (not a `<div>` with `phx-click`).
- Banner is a `<section aria-label="Document change notice">` so it's
  skippable with a landmark jump.

## Mobile considerations

- Toast moves to bottom-center with full-width padding; tap targets ≥44px.
- Banner remains at the top of the doc; on narrow screens the "Mark as read"
  button wraps to a second line rather than truncating.
- Sidebar dots are already part of the tree row; no mobile-specific work.
- Margin change bars: on mobile the left content padding is smaller, so the
  3px bar sits at `padding-left: 0`. Verify it doesn't collide with list
  bullets — if it does, bump the bar to a 4px offset.

## Components to add

- `DocpubWeb.Components.WhatsNew.toast/1` — the global toast.
- `DocpubWeb.Components.WhatsNew.banner/1` — per-doc banner; takes the
  matching `%FileChange{}` as an attr.
- `DocpubWeb.Components.WhatsNew.dot/1` — the tree indicator.
- Colocated hook `.ChangeBars` — reads `data-whats-new-hunks` JSON from a
  container, walks `[data-source-line]` children, applies classes.
- CSS: `.whats-new-added` / `.whats-new-modified` rules in `app.css` with a
  `border-left` in the theme's success/info colors at low opacity.

## Route + controller additions

- `scope "/" do pipe_through [:browser, :vault_auth]`: add
  `post "/whats-new/mark_read", WhatsNewController, :mark_read`.
- `DocpubWeb.WhatsNewController` — single `mark_read/2` action.

## Phased rollout

1. **Phase A (low-risk, high-value):** toast + banner + sidebar dots +
   mark-as-read. No renderer changes. Ships the full user story minus
   in-document highlighting.
2. **Phase B:** source-line annotations in the markdown renderer +
   `hunks_for/1` API + `.ChangeBars` hook + CSS. Adds the margin change
   bars once Phase A is in users' hands.

Each phase is independently useful and shippable.

## Open questions

- [x] Should the toast persist across route changes within one LiveView
      session, or re-appear on every `handle_params`? Current plan: appears
      once per LiveView mount, not per `handle_params`.  Answer: go with current plan 
- [x] Do we want a keyboard shortcut for mark-as-read (e.g. `g m`)? Defer
      unless users ask.  Answer: UI button is fine for now
- [x] Should `:renamed` files where only extension changed (e.g. a `.txt`
      renamed to `.md`) render a banner on the *new* path only? The data
      layer already filters to surfaced extensions, so yes — no extra work.  Answer: whatever you think is best.
