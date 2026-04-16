# Implementation Plan: What's New UI

**Spec:** `_spec/features/260415_whats-new-ui.md`
**Generated:** 2026-04-15

---

## Goal

Build the user-facing surfaces for the What's New feature on top of the
existing `Docpub.WhatsNew` data layer and `DocpubWeb.Plugs.WhatsNew` plug:
a global toast, sidebar markers, a per-document banner, in-document
line-level change bars, and a single mark-as-read action that clears every
indicator at once.

## Scope

### In scope
- Pass the existing `conn.assigns.whats_new` summary into LiveView via session
  and assign it to the socket on mount.
- Phase A surfaces: global toast, sidebar markers (file + folder rollup),
  per-document banner, mark-as-read POST endpoint.
- Phase B: data-layer extension for per-line hunks (cached per `(from, to,
  path)`) and inline left-margin change bars in rendered markdown.
- Accessibility (`aria-label`, polite live region, real `<button>`) and
  responsive variants per spec.

### Out of scope
- Dedicated `/whats-new` route or page.
- Word-level intra-line diff.
- Per-document or per-file mark-as-read.
- Email/push/RSS notifications.
- Keyboard shortcut for mark-as-read.
- Server-side persistence of read state (cookie remains source of truth).
- Welcome/onboarding affordance for first-time visitors.

## Architecture & Design Decisions

1. **Summary handed off via session, not re-computed in LiveView.** The
   plug already builds the `Summary` and stamps the cookie. Persist the
   summary into the session under `:whats_new` so the LiveView mount can
   read it without re-running git. Refreshing the summary on
   `{:vault_changed, ...}` is out of scope for v1 — the user gets the
   updated state on the next full page load (which is when the cookie is
   re-read anyway).
2. **Mark-as-read is a regular HTTP POST.** Phoenix LiveView cannot mutate
   cookies on a websocket frame, and the spec is explicit about this. Add
   `MarkAsReadController` with `POST /whats-new/mark-read`, which advances
   the cookie to current HEAD + now and redirects back via a `redirect_to`
   form param (validated to be a local path).
3. **Change-set lookup is O(1) per node.** Build a `MapSet` of changed
   paths once per render and pass it down to `tree_nodes/1`. For folder
   rollup, also build a `MapSet` of folder ancestors of every changed path
   ("docs", "docs/api", ...) once per render. The recursive `tree_nodes`
   component receives both sets via assigns.
4. **Banner & toast are stateless components in `core_components.ex`.**
   They receive the `Summary` (and current path, for the banner) and
   render conditionally. Toast dismissal is a LiveView event that flips a
   socket assign (`whats_new_toast_dismissed`) — the cookie is untouched.
5. **Phase B extension to the data layer** adds
   `Docpub.WhatsNew.line_hunks(from_sha, to_sha, path)` returning a list
   of `%Hunk{kind: :added | :modified, start_line: int, end_line: int}`,
   memoized in `Docpub.WhatsNew.Cache` keyed by `{from, to, path}`. The
   `Docpub.Markdown` renderer is extended with an optional `:line_marks`
   option; when present, it post-processes the rendered HTML to wrap the
   relevant top-level block elements with a `data-whats-new="added"` or
   `"modified"` attribute. CSS in `app.css` paints the left border.
6. **Visual language** uses semantic daisyUI tokens: `text-success` for
   added, `text-warning` for modified, `text-info` for renamed,
   `text-error` for deleted (matches the existing palette already in use
   in `vault_live.ex`).

## Implementation Steps

### Phase A — Toast, sidebar, banner, mark-as-read

1. **Plumb the summary from plug to session.**
   - Files: `lib/docpub_web/plugs/whats_new.ex`,
     `lib/docpub_web/router.ex`.
   - In the plug, after computing `summary`, call
     `put_session(conn, :whats_new_summary, summary)` so it survives into
     LiveView mount. (Alternative: skip the session round-trip and re-call
     `WhatsNew.summarize(req_cookies[name])` from LiveView mount; prefer
     session to keep mount cheap and to guarantee the plug-computed value
     wins.)

2. **Read the summary in `VaultLive.mount/3`.**
   - Files: `lib/docpub_web/live/vault_live.ex`.
   - Pull `session["whats_new_summary"]` (default `%Summary{}`).
   - Compute `whats_new_paths` (`MapSet` of changed paths) and
     `whats_new_folders` (`MapSet` of all ancestor folders) once at mount
     and recompute on `{:vault_changed, _, _}` (cheap, runs already).
   - Assign `whats_new_summary`, `whats_new_paths`, `whats_new_folders`,
     `whats_new_toast_dismissed: false`.

3. **Create the toast component.**
   - Files: `lib/docpub_web/components/core_components.ex` (new
     `whats_new_toast/1` function component).
   - Renders only when `summary.kind == :diff` AND `length(files) > 0` AND
     not dismissed.
   - Polite ARIA live region (`role="status" aria-live="polite"`).
   - "X files changed since your last visit" with totals from
     `summary.counts`.
   - Two real `<button>` actions: "Dismiss" (`phx-click="whats_new_dismiss"`)
     and "Mark all read" (a `<form method="post" action="/whats-new/mark-read">`
     with hidden `redirect_to` set to the current request path — passed in
     via assign).
   - Responsive: `class="toast toast-top toast-end max-md:toast-bottom max-md:toast-center"`.

4. **Render the toast in the layout.**
   - Files: `lib/docpub_web/components/layouts.ex`.
   - Add `<.whats_new_toast summary={@whats_new_summary}
     dismissed={@whats_new_toast_dismissed} redirect_to={@current_path_uri} />`
     inside `app/1`, alongside `<.flash_group>`. The summary needs to be
     reachable from the layout — pass via attr and have `vault_live.html.heex`
     forward `whats_new_summary={@whats_new_summary}` etc. to
     `<Layouts.app>`.

5. **Handle dismiss event.**
   - Files: `lib/docpub_web/live/vault_live.ex`.
   - `handle_event("whats_new_dismiss", _, socket)` → `assign(socket,
     whats_new_toast_dismissed: true)`. No cookie mutation.

6. **Sidebar markers.**
   - Files: `lib/docpub_web/live/vault_live.ex` (component
     `tree_nodes/1` and helpers).
   - Pass `paths` and `folders` MapSets into `tree_nodes/1` via attrs.
   - For file nodes: when `MapSet.member?(@paths, node.path)`, render a
     small marker (`<span class="size-1.5 rounded-full bg-success" title="Added">`)
     keyed by the change kind. Need a per-path lookup of the change kind —
     extend the assigns with a `whats_new_kind_by_path` map (built
     alongside the MapSet).
   - For folder nodes: when `MapSet.member?(@folders, node.path)` AND the
     folder is not currently expanded, render a faint dot marker
     (`bg-base-content/30`) — collapses cleanly when the folder opens.
   - For renamed files, set `title={"Renamed from " <> previous_path}`.

7. **Per-document banner.**
   - Files: `lib/docpub_web/components/core_components.ex` (new
     `whats_new_banner/1`), `lib/docpub_web/live/vault_live.html.heex`
     (mount above the rendered content for `:markdown` doc type).
   - Renders only when current_path is in the changed set.
   - Shows author + relative timestamp from the matching `%FileChange{}`
     (use `Phoenix.HTML.raw/1`-free helper or a small `relative_time/1`
     helper added to `core_components.ex`).
   - For `:renamed`, append "previously at <previous_path>".
   - Includes a `<form method="post" action="/whats-new/mark-read">` with
     a "Mark as read" button.
   - Marked up as `<section role="region" aria-label="What's new for this
     document">`.

8. **Mark-as-read controller + route.**
   - Files: `lib/docpub_web/controllers/whats_new_controller.ex` (new),
     `lib/docpub_web/router.ex`.
   - `POST /whats-new/mark-read`. Action:
     - Compute current HEAD via `Docpub.WhatsNew.Cache.current_head/0`.
     - Encode a fresh cookie with `Cookie.encode/1`.
     - `put_resp_cookie/4` with `Cookie.options()`.
     - Validate `params["redirect_to"]` starts with `/` and has no host
       component; fall back to `/`.
     - `redirect(to: redirect_to)`.
   - Route lives inside the `:browser` pipeline (no `:vault_auth` needed —
     stamping a cookie is harmless; revisit if the auth model demands it).

9. **First-visit / empty-state silencing.**
   - All Phase A surfaces already gate on `summary.kind == :diff` and
     non-empty changes. Confirm in tests.

### Phase B — Inline line-level change bars

10. **Extend the data layer with hunks.**
    - Files: `lib/docpub/whats_new/git.ex`,
      `lib/docpub/whats_new/cache.ex`, `lib/docpub/whats_new.ex`.
    - Add `Git.line_hunks(from_sha, to_sha, path)` that shells out to `git
      diff --unified=0 <from>..<to> -- <path>` and parses `@@ -a,b +c,d
      @@` headers into `[%Hunk{kind, start_line, end_line}]`. Treat hunks
      whose `b == 0` as `:added`, others as `:modified`.
    - Add `Cache.line_hunks/3` keyed by `{from, to, path}` with the same
      memoization shape as `summary_for/1`.
    - Public API: `Docpub.WhatsNew.line_hunks(from_sha, to_sha, path)`.

11. **Teach the markdown renderer about line marks.**
    - Files: `lib/docpub/markdown.ex`.
    - Accept `:line_marks` option (`[%Hunk{}]`).
    - After mdex renders, walk the top-level block children using
      `LazyHTML` (already a dep) and stamp `data-whats-new="added"` or
      `"modified"` on any block whose source line range overlaps a hunk.
    - mdex sourcepos: enable `extension: [sourcepos: true]` so each block
      carries `data-sourcepos="line:col-line:col"`; parse it during the
      walk. (Verify the option name against the installed mdex version
      during implementation.)

12. **Wire renderer call site to pass hunks.**
    - Files: `lib/docpub_web/live/vault_live.ex` (`load_document/2`).
    - When `summary.kind == :diff` and `current_path` is in the change
      set, fetch hunks via `Docpub.WhatsNew.line_hunks/3` and pass them
      as `:line_marks` to `Markdown.render/2`.

13. **CSS for change bars.**
    - Files: `assets/css/app.css`.
    - `[data-whats-new="added"] { border-left: 3px solid var(--color-success); padding-left: 0.5rem; }`
      and `:modified` with `--color-warning`. Use Tailwind utility classes
      via `@layer components` if cleaner; do NOT use `@apply` (per
      project conventions).
    - Add `aria-label`/`title` via the renderer at the same time so the
      bars are not color-only.

14. **Narrow-screen safety.**
    - Files: `assets/css/app.css`.
    - Add a media-query reduction (`padding-left: 0.25rem; border-width:
      2px;`) for `<= 640px` so the bars don't collide with list bullets.

## Dependencies & Ordering

- Steps 1–2 must land before any other Phase A step (everything reads the
  socket assigns).
- Step 8 (controller + route) must land before steps 3 and 7 can be
  exercised end-to-end, but the components in 3/7 can be drafted in
  parallel.
- Step 6 depends on step 2 (paths MapSet) but is otherwise standalone.
- Phase B (10–14) depends on all of Phase A being merged. Step 10 is the
  only blocker for steps 11–13; step 14 can land last.

## Edge Cases & Risks

- **Cookie can't be set on a LiveView frame.** Mitigated by step 8 — POST
  controller. If we ever want a single-click LiveView UX, we'd need a
  JS-driven `fetch` to the controller, which is an enhancement, not v1.
- **`redirect_to` open-redirect.** Validate path is absolute-local with no
  scheme/host in step 8 (e.g. `String.starts_with?(rt, "/") and not
  String.starts_with?(rt, "//")`).
- **Stale summary on long-lived LiveView sessions.** A user who marks
  read, then navigates within the same LiveView, won't see the toast/
  banner because we set `dismissed = true` after the POST round-trip
  fully reloads the socket. Confirm: mark-as-read does a full HTTP
  redirect, which kills and remounts the LiveView — so the new summary
  comes through naturally. No special handling needed.
- **Vault watcher fires mid-session.** `{:vault_changed, ...}` already
  rebuilds the tree; we should also clear the summary (set `kind:
  :no_baseline`) until the next full request, to avoid pointing at
  stale changed paths. Simpler: leave the summary alone — it's still
  correct relative to the cookie's `from_sha`. Document this in the
  handler.
- **Sourcepos accuracy in mdex.** mdex's sourcepos for transformed
  constructs (wikilinks, mermaid) may not survive the regex
  post-processing. Test on documents with each construct; fall back to
  decorating the surrounding block.
- **O(1) folder rollup.** Computing the ancestor set is `O(total changes
  × avg path depth)`, done once per render — fine for any realistic
  vault. Document the assumption.
- **Renamed files where only extension changed.** Spec confirms: data
  layer already filters surfaced extensions, so no special handling.
- **First-visit silence:** `summary.kind == :no_baseline` short-circuits
  every component. Add a regression test.
- **Cookie name collision / signing key rotation.** Out of scope;
  `Cookie.decode/1` already returns `:error` and the plug handles it.

## Testing Strategy

- **Unit:**
  - `Docpub.WhatsNew.Git.line_hunks/3` against fixture commits in a
    throwaway git repo (use `start_supervised!/1` for setup).
  - `Docpub.WhatsNew.Cache.line_hunks/3` memoization.
  - Markdown renderer with `:line_marks` — assert `data-whats-new`
    attributes appear on the right blocks, with correct `aria-label`.
  - `redirect_to` validation in `WhatsNewController`.
- **LiveView (Phoenix.LiveViewTest):**
  - Toast renders when summary has changes; absent when `:no_baseline`
    or empty.
  - Toast dismiss event hides the toast in the same socket.
  - Sidebar markers present on changed file nodes (assert via DOM IDs:
    add `id={"tree-#{node.path}"}` to each row first).
  - Folder rollup marker present on collapsed ancestor folders.
  - Banner present only when `current_path` is in the change set.
- **Controller test:**
  - POST `/whats-new/mark-read` sets the cookie to current HEAD and
    redirects to the validated path. Subsequent request gets an empty
    summary.
- **Manual:**
  - Make a few commits in a local vault, ensure the toast counts
    match, click "Mark all read", confirm everything clears.
  - Verify mobile layout (toast bottom-center, banner wrapping).
  - Verify Phase B: introduce changes spanning several markdown blocks;
    confirm correct margin bars on rendered HTML.

## Open Questions

- [x] Confirm the installed mdex version supports `sourcepos: true` and
      surfaces it as `data-sourcepos` on output blocks (or whether we need
      a manual mapping). If it doesn't, Phase B may need a different
      strategy (e.g. line-by-line markdown chunking).  Answer: you're going to have to confirm that
- [x] Should the mark-as-read POST go through `:vault_auth`? Defaulting to
      `:browser` only — confirm with project owner before merging if there
      is a multi-tenant story.  Answer: browser only is ok 
- [x] Should the toast render on the login page if a logged-out user
      somehow has a cookie? Current router scopes the plug only to
      `:browser`-pipelined routes that include login — recommend
      conditioning render on `current_user`-style assign to be safe.  Answer: don't render any change info on the login page
- [x] The session-passthrough in step 1 means stale summaries persist for
      the duration of a session if the user opens new tabs. Acceptable for
      v1, but worth flagging if engagement metrics matter.  Answer: ok 
