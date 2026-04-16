# What's New UI

## Summary

Phase 2 of the "What's New" feature: build the user-facing surfaces that
expose vault changes since a visitor's last visit. Consumes the data layer
delivered in Phase 1 (`Docpub.WhatsNew`) and surfaces changes contextually
through a global toast, sidebar indicators, a per-document banner, and
in-document line-level change bars. A single mark-as-read action clears all
indicators at once. No dedicated `/whats-new` route is introduced.

## Goals

- Make vault changes discoverable without requiring users to seek them out
- Surface change information in-context (tree, document header, document body)
- Offer a single, vault-wide acknowledgement that clears every indicator
- Keep the feature unobtrusive: silent for first-time visitors and when there
  is nothing new to show
- Ship in two independently useful sub-phases so the highlight-in-document
  work does not block the simpler surfaces

## Non-Goals

- A dedicated `/whats-new` page or route
- Intra-line word-level diff highlighting (line-level only)
- Per-document or fine-grained acknowledgement (mark-as-read is whole-vault)
- Any out-of-app notification (email, push, RSS, etc.)
- Keyboard shortcuts for mark-as-read in v1
- A "welcome" affordance for first-time visitors
- Server-side persistence of read state (cookie remains the source of truth)

## User Stories

1. **Returning visitor toast**: As a returning visitor, when I load any page
   while changes exist, I see a dismissible toast telling me how many docs
   have changed since my last visit, with options to dismiss or mark all read.
2. **Sidebar awareness**: As a visitor browsing the tree, I can see at a
   glance which files in the sidebar have changed since my last visit, and
   which folders contain changed descendants, without expanding every folder.
3. **Per-document context**: As a visitor opening a changed document, I see a
   banner at the top identifying who changed it and when, with a "Mark as
   read" action. For renamed files the banner notes the previous path.
4. **In-document change bars**: As a visitor reading a changed document, I
   can see exactly which lines are new or modified via colored bars in the
   left margin of the rendered page.
5. **One-click acknowledgement**: As a visitor, a single click on "Mark as
   read" — from the toast, the banner, or any other affordance — advances my
   cookie to current HEAD and clears every indicator across the app.
6. **First visit silence**: As a first-time visitor with no baseline, I see
   no toast, no banner, and no dots; the feature is invisible until I have a
   real baseline to compare against.
7. **Empty state silence**: As a returning visitor who has already seen
   everything, no UI is drawn — there is nothing to draw attention to.

## Functional Requirements

### Global toast

- Shown once per LiveView mount when there are changes to report
- Dismiss action closes the toast for the current LiveView session only
  (cookie untouched); a page reload re-shows it until the user marks read
- Mark-as-read action advances the cookie and clears all indicators
- Suppressed entirely when there is no baseline or no changes
- No auto-dismiss timer; the user must act or navigate away

### Sidebar change indicator

- Each tree node whose path is in the change set renders a small colored
  marker keyed by change kind:
  - added, modified, renamed, deleted (deleted nodes are not visible in the
    tree in practice since the tree only shows files present at HEAD)
- Renamed entries expose the previous path via tooltip
- Folder nodes containing any changed descendant render a faint marker so
  users can see where to drill in without expanding every folder
- Membership lookup must be O(1) per node; computation is performed once per
  render, not per node

### Per-document banner

- Rendered at the top of the document view when the currently viewed path is
  in the change set
- Shows author and a relative timestamp of the last commit that touched the
  file in the range
- For renamed files, includes the previous path
- Offers a "Mark as read" action; no per-document dismiss (would desync from
  sidebar markers)
- Suppressed when there is no baseline, no changes, or the current document
  is unchanged

### Inline line-level change bars

- Rendered inside the markdown body as a colored left-border on each changed
  line block (added vs. modified are visually distinct)
- No deleted-line markers inside the body; deleted files surface only via
  the toast count
- No intra-line word-level highlighting; a whole modified line is marked
  regardless of how much of it changed
- Diff baseline is the visitor's cookie baseline, not the previous commit,
  so a long-absent visitor sees everything since *their* last visit
- Requires per-line diff information not currently emitted by the data
  layer; the data layer must be extended to provide it on demand for the
  currently viewed document, with results cached per `(from, to, path)`

### Mark-as-read flow

- All "Mark as read" affordances trigger the same server action that:
  - Advances the cookie's recorded commit to current HEAD
  - Advances the cookie's recorded visit time to now
  - Returns the user to where they were
- Implemented as a regular HTTP POST (not a LiveView event), since cookies
  can only be stamped on a regular HTTP response
- After the round-trip, the page repopulates with no changes and all
  indicators disappear

### State handling

- No baseline (first visit or stale/unknown cookie commit): no toast, no
  banner, no markers
- Empty change set: no toast, no banner, no markers
- Non-empty change set: all four surfaces are eligible to render based on
  context

## UI/UX Requirements

### Visual language

- Color coding is consistent across surfaces: added, modified, renamed, and
  deleted each have a distinct, theme-aware color drawn from the existing
  daisyUI palette
- Markers and bars are deliberately small and low-contrast so they inform
  without dominating the page
- The banner uses a tinted background and a recognizable icon to read as a
  notice rather than as document content

### Accessibility

- All color-coded markers and bars carry equivalent text via `title` /
  `aria-label` ("Added", "Modified", etc.) so colorblind users and screen
  readers receive the same signal
- The toast is a polite live region and uses a real `<button>` for actions,
  not click-handled `<div>`s
- The banner is a labeled landmark region so it can be skipped by keyboard
  and AT users

### Responsive behavior

- Toast: top-end on desktop, bottom-center on mobile, with full-width
  padding and tap targets sized for touch
- Banner: remains at the top of the document on mobile; the action wraps
  rather than truncating on narrow screens
- Sidebar markers: no mobile-specific work; they ride along with each row
- Margin change bars: must not visually collide with list bullets or other
  body content at narrow widths

### Phasing

- **Phase A** (low-risk, high-value): toast, banner, sidebar markers, and
  mark-as-read. No renderer changes. Delivers the full user story minus
  in-document highlighting.
- **Phase B**: in-document change bars, including the data-layer extension
  needed to produce per-line hunk information. Adds margin highlighting on
  top of Phase A.
- Each phase must be independently useful and shippable.

## Open Questions

- [x] Should the toast persist across route changes within one LiveView
      session, or re-appear on every `handle_params`? **Answer:** appears
      once per LiveView mount, not per `handle_params`.
- [x] Should there be a keyboard shortcut for mark-as-read (e.g. `g m`)?
      **Answer:** not in v1 — the UI button is sufficient until users ask.
- [x] For `:renamed` files where only the extension changed (e.g. `.txt` to
      `.md`), should the banner render only on the new path? **Answer:**
      yes; the data layer already filters to surfaced extensions, so this
      requires no extra work.
