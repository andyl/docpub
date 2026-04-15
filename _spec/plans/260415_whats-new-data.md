# Implementation Plan: What's New Data

**Spec:** `_spec/features/260415_whats-new-data.md`
**Generated:** 2026-04-15

---

## Goal

Build the data layer for the "What's New" feature: a signed Phoenix cookie
that records each visitor's last-visit commit/date, plus a `Docpub.WhatsNew`
module that, given that cookie, returns a structured summary of vault changes
between the recorded commit and the current `HEAD`. No UI in this phase.

## Scope

### In scope
- `Docpub.WhatsNew` module: canonical entry point producing the change summary
- `Docpub.WhatsNew.Cookie` (or equivalent) helpers for reading/writing the
  signed cookie via `Plug.Conn.put_resp_cookie/4` with `:signed` (or via
  `Plug.Conn` cookie machinery using `Phoenix.Token`)
- `Docpub.WhatsNew.Git` adapter that shells out to `git` to:
  - Resolve current `HEAD` for the vault repo
  - Verify a commit SHA exists in the repo
  - Diff `from..HEAD` and produce per-file change records (status, prev path,
    last commit SHA / author / timestamp, lines added/removed)
- A small `GenServer` (`Docpub.WhatsNew.Cache`) that holds the current HEAD
  and a small LRU/map of computed summaries keyed by `{from_commit, to_commit}`
  - Refreshes HEAD on a timer and on `:vault_changed` PubSub messages
- Filtering of results to vault-served file types (markdown, images, pdf)
- Plug or shared helper that the existing browser pipeline uses to read the
  cookie on request and stamp the refreshed cookie on the response
- Tests covering all five user-story scenarios

### Out of scope
- Any LiveView, controller view, or template change that exposes results
- UI surfaces: badges, change bars, summary pages, navigation entries
- Per-element/in-document diff rendering
- Server-side per-user state beyond the cookie

## Architecture & Design Decisions

### Module layout
- `Docpub.WhatsNew` — public API. One function:
  `summarize(cookie_value | nil) :: {:ok, summary, new_cookie_value}`.
  Returns the change summary plus the cookie value the caller should write
  back. Hides cache + git + cookie details from callers.
- `Docpub.WhatsNew.Cookie` — encode/decode + cookie name/options. Uses
  `Phoenix.Token.sign/verify` against the endpoint's secret so the cookie is
  tamper-proof; payload is a plain map `%{last_visit_date: iso8601,
  last_git_commit: sha}`.
- `Docpub.WhatsNew.Git` — pure adapter around `System.cmd("git", ...)` run
  inside the vault path. Returns Elixir data structures; no I/O concerns
  leaked to callers. Encapsulates: `head/0`, `commit_exists?/1`,
  `diff_range/2`, `last_commit_for_file/3`.
- `Docpub.WhatsNew.Cache` — `GenServer` started under the supervision tree.
  Tracks current HEAD, refreshes on a 30-second timer and on
  `Docpub.VaultWatcher` PubSub events, and memoises summaries by
  `{from, to}`. Cache size capped (e.g. 64 entries) to bound memory.
- `Docpub.WhatsNew.Summary` — small struct/module defining the shape of the
  returned data so consumers (Phase 2 LiveView/controllers) have a stable
  contract.

### Why shell out to `git` rather than add a dep
The repo already trusts the on-disk Git CLI (it is a self-hosted vault
viewer). Adding a Git library is more dependency surface than is justified
for the small set of plumbing commands required. `System.cmd` with explicit
`cd:` keeps the surface area small and easily testable via fixture repos.

### Cookie shape and lifetime
- Name: `_docpub_last_visit`
- `max_age: 60 * 60 * 24 * 30` (30 days, per spec answer)
- `http_only: true`, `same_site: "Lax"`, `secure: true` in prod
- Encoded with `Phoenix.Token.sign(endpoint, "last_visit", payload)` and
  decoded with `Phoenix.Token.verify(endpoint, "last_visit", value,
  max_age: 30 * 86400)`

### Failure modes → "no baseline"
The `Docpub.WhatsNew.summarize/1` function never raises. It returns a
summary with `kind: :no_baseline` (and an empty file list) whenever:
- the cookie is missing or fails verification
- the recorded commit is unknown to the repo
- the vault path is not a Git repo
- any underlying `git` command fails

In all cases the returned cookie value is the freshly-stamped current state,
so the next visit gets a real comparison baseline.

### Summary struct shape

```elixir
%Docpub.WhatsNew.Summary{
  kind: :diff | :empty | :no_baseline,
  from_commit: String.t() | nil,
  to_commit: String.t(),
  from_date: DateTime.t() | nil,
  to_date: DateTime.t(),
  files: [%FileChange{
    path: String.t(),
    previous_path: String.t() | nil,
    change: :added | :modified | :renamed | :deleted,
    last_commit_sha: String.t(),
    last_commit_author: String.t(),
    last_commit_date: DateTime.t(),
    lines_added: non_neg_integer(),
    lines_removed: non_neg_integer()
  }],
  counts: %{added: integer, modified: integer, renamed: integer, deleted: integer}
}
```

Files sorted by `last_commit_date` descending.

## Implementation Steps

1. **Define the `Summary` and `FileChange` structs**
   - Files: `lib/docpub/whats_new/summary.ex`, `lib/docpub/whats_new/file_change.ex`
   - Pure data types with `@type t` and `defstruct`. No behaviour.

2. **Implement the Git adapter**
   - Files: `lib/docpub/whats_new/git.ex`
   - Functions: `head(repo_path)`, `commit_exists?(repo_path, sha)`,
     `diff_range(repo_path, from_sha, to_sha)`,
     `commit_meta(repo_path, sha)`.
   - `diff_range` invokes `git -C <path> log --name-status --numstat
     --format=...` (or pairs `git diff --name-status -M` with `git log
     --numstat`) and parses output into `FileChange` records.
   - Detect renames via `-M` and emit a single `:renamed` entry (per spec
     answer).
   - Filter results to extensions surfaced by `Docpub.Vault` (markdown,
     image, pdf) — reuse the predicate from `Docpub.Vault` (extract a
     small helper if necessary so the lists stay single-sourced).

3. **Implement the cookie module**
   - Files: `lib/docpub/whats_new/cookie.ex`
   - `name/0`, `options/0`, `encode(payload, conn)`, `decode(value, conn)`.
   - Uses `Phoenix.Token` keyed off `DocpubWeb.Endpoint`. `decode` returns
     `{:ok, payload}` or `:error` for any verification/parse failure.

4. **Implement the cache GenServer**
   - Files: `lib/docpub/whats_new/cache.ex`
   - State: `%{head: sha | nil, head_date: dt | nil, summaries: %{}}`.
   - On `init`, computes HEAD, schedules a refresh every 30 s, and calls
     `Docpub.VaultWatcher.subscribe/0` so it can refresh on
     `:vault_changed` messages.
   - Public API: `current_head/0`, `summary_for(from_sha)`.
   - `summary_for/1` checks the memo, else delegates to
     `Docpub.WhatsNew.Git` and stores. LRU-style cap at 64 entries.

5. **Wire the cache into the supervision tree**
   - Files: `lib/docpub/application.ex`
   - Add `Docpub.WhatsNew.Cache` after `Docpub.VaultWatcher` so PubSub is
     ready. Guard for "no vault path" / "vault not a Git repo" by having
     the GenServer return `:ignore` from `init/1` in that case (mirrors
     `VaultWatcher`).

6. **Implement the public façade**
   - Files: `lib/docpub/whats_new.ex`
   - `summarize(cookie_value_or_nil)` returns `{summary, new_cookie_value}`.
     Decodes cookie → asks cache for the summary → builds a fresh cookie
     payload from the current HEAD + `DateTime.utc_now()`.
   - Always returns a fresh cookie value (so callers can unconditionally
     write it back).

7. **Add a Plug helper for the browser pipeline** *(thin, no UI surface)*
   - Files: `lib/docpub_web/plugs/whats_new.ex`,
     `lib/docpub_web/router.ex`
   - `call/2` reads the cookie, calls `Docpub.WhatsNew.summarize/1`,
     `assign`s the summary on `conn`, and writes the refreshed cookie via
     `Plug.Conn.put_resp_cookie/4` with the options from
     `Docpub.WhatsNew.Cookie`.
   - Insert into the `:browser` (or protected) pipeline so both controllers
     and LiveViews can read the assign in Phase 2. No template touches it
     yet.

8. **Tests**
   - Files: `test/docpub/whats_new/git_test.exs`,
     `test/docpub/whats_new/cookie_test.exs`,
     `test/docpub/whats_new_test.exs`,
     `test/docpub_web/plugs/whats_new_test.exs`
   - `git_test`: build temp repos in `tmp/` with `System.cmd("git", ...)`,
     create commits exercising add/modify/rename/delete, assert parsed
     output. Cover: equal HEAD → empty, unknown SHA → `:no_baseline`,
     not-a-repo → `:no_baseline`.
   - `cookie_test`: round-trip encode/decode, tampered value → `:error`,
     expired token → `:error`.
   - `whats_new_test`: end-to-end with a fixture repo, verifying the
     returned cookie always reflects current HEAD even on the
     `no_baseline` path.
   - `plug_test`: assigns set, response cookie present and signed.

9. **Run `mix precommit` and address warnings**
   - Files: n/a
   - Confirm formatter clean, no compile warnings, all tests pass.

## Dependencies & Ordering

- Steps 1 → 2 → 3 are independent; do 1 first since 2 and the cache
  reference its types.
- Step 4 (cache) depends on 2 (Git adapter) and on `VaultWatcher`
  (already exists).
- Step 5 depends on 4.
- Step 6 (façade) depends on 3 + 4.
- Step 7 (plug) depends on 6.
- Tests in Step 8 can be drafted alongside their target modules; the
  full suite is the gate before Step 9.

## Edge Cases & Risks

- **History rewrite / force push**: per spec answer, ignored — surfaces
  as "unknown commit" → `:no_baseline`. Cache invalidation handled by
  PubSub + timer refresh of HEAD.
- **Initial visit (no cookie)**: `summarize(nil)` returns `:no_baseline`
  summary and a fresh cookie.
- **Vault is not a Git repo**: every `git` call returns non-zero;
  adapter returns `{:error, :not_a_repo}`; façade returns
  `:no_baseline`; cache `init/1` returns `:ignore`.
- **Performance**: rename detection (`git log -M --numstat`) is `O(diff
  size)`. The summary memo prevents repeated cost for the same
  `(from, to)` across multiple page loads. Bound the cache to 64 entries
  to avoid unbounded growth in multi-tenant or multi-user scenarios.
- **Cookie size**: payload is two short strings → well under the 4 KB
  limit even after signing.
- **Path filtering vs. renames**: when only one side of a rename is a
  surfaced extension (e.g. renamed `.md` to `.txt`), treat as
  `:deleted`; mirror the inverse case as `:added`. Document this in the
  Git adapter.
- **Race between cache HEAD and disk HEAD**: acceptable per spec — at
  worst a visit sees a slightly stale HEAD; next refresh fixes it.

## Testing Strategy

- Unit-test the Git adapter against ephemeral repos created in `tmp/`
  via `System.cmd`. Use `start_supervised!/1` for any helper processes;
  use `Process.monitor/1` + `assert_receive` rather than `Process.sleep/1`.
- Unit-test the cookie module via `Phoenix.Token` round-trips against a
  test endpoint secret.
- Unit-test the façade with a fixture repo + a fake cache (or by
  starting a real one under `start_supervised!`).
- Plug test using `Phoenix.ConnTest`: assert assign + `resp_cookies`
  contains a signed value.
- Manual smoke check: start the dev server, hit `/`, observe the
  `_docpub_last_visit` cookie set; commit a markdown file in the vault,
  reload, confirm via `IEx.pry` or a temporary log that the assign
  contains the expected change record.

## Open Questions

- [x] Should the cache key on the *full* `(from, to)` pair, or only on
      `from` (since `to` is always current HEAD at compute time)? Keying
      on the pair is safer if we ever expose historical comparisons.  Answer: only on from.  Not interested in historical comparisons.
- [x] Is shelling out to `git` acceptable in the project's deployment
      environment, or should we add a Git dependency (e.g. `git_cli`)
      for explicit declaration? Current plan assumes the former.  Answer: shelling to git is ok
- [x] What is the desired behaviour when `git` is not installed at all
      on the host? Treat the same as "not a repo" (`:no_baseline`)?  Answer: sure treat the same as :no_baseline.  Perpetual no baseline
- [x] For renames where only one side is a surfaced extension, is the
      proposed `:deleted` / `:added` collapse acceptable, or should
      such files be filtered out entirely?  Answer: what ever is simpler 
