# Implementation Plan: Obsidian Vault Viewer

**Spec:** `_spec/features/260406_obsidian-vault-viewer.md`
**Generated:** 2026-04-06

---

## Goal

Build a Phoenix LiveView application that serves an Obsidian vault over the
web, allowing users to browse a sidebar file tree, view rendered markdown (with
wiki-links and Mermaid), edit/create/delete documents, and search — all backed
by direct filesystem reads/writes with no database.

## Scope

### In scope
- CLI escript launcher with options (port, host, auth, initial-page, help, version)
- Sidebar navigation tree reflecting vault directory structure
- Markdown rendering with wiki-links, Mermaid diagrams, and syntax highlighting
- Toggle between view and edit modes
- CRUD operations on documents (create, edit, delete)
- Full-text search across vault documents
- Password authentication (optional, via CLI flag)
- Responsive layout (desktop + mobile)
- Cookie-based "last visited page" persistence
- Unique URL per document for bookmarking
- Display of PDFs and images in the sidebar and viewer

### Out of scope
- Chat, presence, OIDC auth, auto-tunneling, UML/PlantUML
- Real-time collaborative editing (Yjs/CRDT)
- Database / Ecto

## Architecture & Design Decisions

### Vault context module (`Docpub.Vault`)
All filesystem operations live in a single context module. It walks the vault directory, reads/writes files, and builds the file tree data structure. No GenServer needed initially — the vault path is stored in application config at boot (set by the CLI). The file tree is loaded upfront on mount since vaults are expected to be small.

### Markdown rendering
Use the `mdex` library (Rust NIF, CommonMark + GFM + wiki-links via comrak). It supports syntax highlighting out of the box. For Mermaid diagrams, detect ````mermaid` fenced blocks and render them client-side via a colocated LiveView hook that loads the Mermaid JS library.

### Wiki-link resolution
Parse `[[Target]]` and `[[Target|Display]]` patterns from rendered HTML. Resolve targets against the vault file tree (case-insensitive, with or without `.md` extension). Convert to `<.link navigate={~p"/doc/path/to/target"}>` style hrefs. Unresolved links render as plain text with a "not found" style (per spec: show a 404, not a create prompt).

### LiveView structure
A single LiveView (`DocpubWeb.VaultLive`) handles the main interface. It uses `handle_params` to derive the current document path from the URL. The sidebar, viewer, and editor are regions within this single LiveView — no LiveComponents needed unless complexity demands it.

### Routing scheme
- `GET /` — redirects to initial page (from CLI flag or cookie)
- `GET /doc/*path` — view/edit a document (LiveView)
- `GET /search?q=term` — search results (could be same LiveView with different state)
- `POST /login` — password auth (if enabled)

### Authentication
When `--auth password` is set, a Plug in the router pipeline checks for a session token. If missing, redirects to a simple login LiveView. Password is stored in application config at boot.

### Escript / CLI
Use `Burrito` or a simple `Mix.Tasks.Docpub.Serve` task initially, evolving to a proper escript. The CLI parses args, sets application config, and starts the Phoenix endpoint. For the initial implementation, a Mix task is simpler and avoids release complexity.

### File watching
In initial scope, add `FileSystem` (inotify wrapper) to push live updates when vault files change on disk.

## Implementation Steps

### Phase 1: Core Infrastructure

1. **Add dependencies**
   - Files: `mix.exs`
   - Add `mdex` (markdown rendering), `file_system` (optional, for future watching)
   - Run `mix deps.get`

2. **Create the Vault context module**
   - Files: `lib/docpub/vault.ex`
   - Functions: `list_tree(vault_path)` returns a nested tree structure of `%{name, path, type, children}` where type is `:folder`, `:markdown`, `:image`, `:pdf`, or `:other`
   - Functions: `read_file(vault_path, relative_path)` returns `{:ok, content}` or `{:error, reason}`
   - Functions: `write_file(vault_path, relative_path, content)` writes content to disk
   - Functions: `create_file(vault_path, relative_path, content)` creates a new file (errors if exists)
   - Functions: `delete_file(vault_path, relative_path)` deletes a file
   - Functions: `search(vault_path, query)` performs full-text grep across `.md` files, returns list of `%{path, matches}` with surrounding context
   - The vault path comes from `Application.get_env(:docpub, :vault_path)`
   - Filter out hidden files/dirs (starting with `.`) and common ignores (`node_modules`, `_build`)

3. **Create the Markdown rendering module**
   - Files: `lib/docpub/markdown.ex`
   - Functions: `render(markdown_string, opts)` returns safe HTML
   - Uses `mdex` for CommonMark + GFM rendering with syntax highlighting
   - Post-processes HTML to convert `[[wiki-links]]` to `<a href="/doc/...">` with proper resolution against a provided file tree
   - Detects unresolved wiki-links and marks them with a CSS class (e.g., `vault-link-broken`)
   - Rewrites image references (`![[image.png]]` and `![](image.png)`) to point to a served file route

4. **Configure vault path in application**
   - Files: `lib/docpub/application.ex`, `config/config.exs`, `config/dev.exs`
   - Add `:vault_path` config key, defaulting to current directory in dev
   - Pass vault_path into application env on startup

### Phase 2: Routing & LiveView

5. **Update the router**
   - Files: `lib/docpub_web/router.ex`
   - Add `live "/doc/*path", VaultLive` route in the browser scope
   - Add `get "/vault_file/*path", VaultFileController, :show` for serving raw files (images, PDFs)
   - Redirect `GET /` to the initial page (from config or cookie)
   - Keep the existing `PageController.home` or replace it with the redirect

6. **Create VaultFileController for raw file serving**
   - Files: `lib/docpub_web/controllers/vault_file_controller.ex`
   - Serves raw binary files (images, PDFs) from the vault directory
   - Sets appropriate content-type headers
   - Guards against path traversal (no `..` allowed)

7. **Create the main VaultLive LiveView**
   - Files: `lib/docpub_web/live/vault_live.ex`
   - `mount/3`: Load file tree from `Docpub.Vault.list_tree/1`, assign to socket. Check cookie for last visited page if no path given.
   - `handle_params/3`: Parse `*path` param, read the document, render markdown, assign `:current_doc`, `:rendered_html`, `:mode` (`:view` or `:edit`). Set cookie for last visited page.
   - `handle_event("toggle_mode", ...)`: Switch between view and edit mode
   - `handle_event("save", ...)`: Write edited content to disk via `Docpub.Vault.write_file/3`, re-render, switch to view mode
   - `handle_event("delete", ...)`: Delete file, navigate to parent or home
   - `handle_event("create", ...)`: Create new file in current directory
   - `handle_event("search", ...)`: Run search, assign results
   - `handle_event("toggle_sidebar", ...)`: Toggle sidebar visibility (mobile)

8. **Create the VaultLive template**
   - Files: `lib/docpub_web/live/vault_live.html.heex`
   - Wrap in `<Layouts.app flash={@flash}>`
   - Three-region layout: sidebar (file tree), main content (viewer/editor), search overlay
   - Sidebar: recursive tree rendering with collapsible folders, current doc highlighted
   - Viewer: rendered HTML output with prose styling
   - Editor: textarea with raw markdown, save/cancel buttons
   - Search: input field + results list
   - Responsive: sidebar as drawer on mobile with toggle button

### Phase 3: Client-Side Rendering

9. **Add Mermaid diagram support**
   - Files: `assets/js/app.js` or colocated hook in the template
   - Create a colocated hook (`.MermaidRenderer`) that finds `<pre><code class="language-mermaid">` blocks and renders them using Mermaid.js
   - Download mermaid.min.js to `assets/vendor/` and import it
   - The hook should re-render on LiveView updates (`updated()` callback)

10. **Add code block copy button (nice-to-have)**
    - Colocated hook that adds a "copy" button to rendered code blocks

### Phase 4: Search

11. **Implement search functionality**
    - Files: `lib/docpub/vault.ex` (add `search/2`), update VaultLive
    - Walk all `.md` files, read content, perform case-insensitive substring match
    - Return file path, matching line numbers, and surrounding context (2 lines before/after)
    - In the LiveView, search results display as a list of links with snippets
    - Search triggers on form submit (not on every keystroke, to keep it simple)

### Phase 5: Authentication

12. **Create auth plug**
    - Files: `lib/docpub_web/plugs/vault_auth.ex`
    - Check `Application.get_env(:docpub, :auth)` — if `:none`, pass through
    - If `:password`, check session for `:authenticated` flag
    - If not authenticated, redirect to `/login`

13. **Create login page**
    - Files: `lib/docpub_web/live/login_live.ex`, `lib/docpub_web/live/login_live.html.heex`
    - Simple form with password field
    - On submit, compare against configured password
    - On success, set session flag and redirect to `/` or original destination

14. **Wire auth into router**
    - Files: `lib/docpub_web/router.ex`
    - Add `VaultAuth` plug to the browser pipeline (conditionally)
    - Add `/login` route outside the auth-protected scope

### Phase 6: CLI

15. **Create Mix task for launching**
    - Files: `lib/mix/tasks/docpub.serve.ex`
    - Parse CLI args: `--port`, `--host`, `--auth`, `--auth-password`, `--initial-page`, `--help`, `--version`
    - Set application env from parsed args
    - Start the Phoenix endpoint
    - Print help text on `--help`, version on `--version`
    - Default vault path to first positional arg or current directory

16. **Create escript configuration (future)**
    - Files: `mix.exs`
    - Add `escript: [main_module: Docpub.CLI]` to project config
    - Create `lib/docpub/cli.ex` as the escript entry point
    - This step can be deferred — the Mix task works fine for development

### Phase 7: Polish & Testing

17. **Style the UI**
    - Files: `assets/css/app.css`, templates
    - Prose styling for rendered markdown (use Tailwind typography or manual)
    - Sidebar tree styling with indentation, folder/file icons
    - Mobile responsive layout with sidebar drawer
    - Edit mode textarea styling
    - Search results styling

18. **Write tests for Vault context**
    - Files: `test/docpub/vault_test.exs`
    - Create a temporary vault directory in setup
    - Test `list_tree/1` with nested folders, various file types
    - Test `read_file/2`, `write_file/3`, `create_file/3`, `delete_file/2`
    - Test `search/2` with matching and non-matching queries
    - Test path traversal protection

19. **Write tests for Markdown rendering**
    - Files: `test/docpub/markdown_test.exs`
    - Test basic markdown rendering
    - Test wiki-link resolution (existing target, missing target, display text variant)
    - Test image reference rewriting
    - Test Mermaid code blocks are preserved (client renders them)

20. **Write tests for VaultLive**
    - Files: `test/docpub_web/live/vault_live_test.exs`
    - Test document viewing (mount with path, check rendered content)
    - Test mode toggling (view → edit → view)
    - Test document editing (save event writes to disk)
    - Test sidebar navigation
    - Test search flow
    - Use a temporary vault directory in test setup

21. **Write tests for authentication**
    - Files: `test/docpub_web/plugs/vault_auth_test.exs`, `test/docpub_web/live/login_live_test.exs`
    - Test pass-through when auth is `:none`
    - Test redirect to login when not authenticated
    - Test successful login
    - Test incorrect password

## Dependencies & Ordering

- **Phase 1 (steps 1-4)** must come first — everything else depends on the Vault context and markdown rendering
- **Step 2 before step 3** — markdown module needs the file tree for wiki-link resolution
- **Step 5 before steps 7-8** — LiveView needs routes defined
- **Step 6 before step 8** — template image tags need the file serving route
- **Phase 3 (step 9)** can happen in parallel with Phase 4-5 since it's purely client-side
- **Phase 5 (steps 12-14)** is independent and can be done in parallel with Phase 3-4
- **Phase 6 (steps 15-16)** can happen anytime after Phase 2
- **Phase 7 (steps 17-21)** should come last but tests for each module can be written alongside

## Edge Cases & Risks

- **Path traversal attacks**: The vault file controller and all vault context functions must reject paths containing `..` or absolute paths. Validate that resolved paths stay within the vault root.
- **Large files**: Binary files (images, PDFs) should be streamed, not loaded entirely into memory. Use `Plug.Conn.send_file/3` in the controller.
- **File encoding**: Assume UTF-8 for markdown files. Handle non-UTF-8 gracefully (show error rather than crash).
- **Concurrent edits**: Since there's no locking, two browser tabs editing the same file could overwrite each other. Accept this limitation per spec (no CRDT). Last write wins.
- **Symlinks**: Decide whether to follow symlinks in the vault tree. Safest to skip them to avoid loops and escaping the vault root.
- **Wiki-link ambiguity**: `[[Page]]` could match `Page.md`, `subfolder/Page.md`, etc. Resolve by preferring the closest match to the current document's directory, then fall back to first match alphabetically.
- **Empty vault**: Handle gracefully — show a "no documents" message rather than crashing.
- **Special characters in filenames**: URL-encode paths in routes. Ensure round-trip fidelity between filesystem paths and URL paths.
- **Mermaid JS size**: Mermaid.js is ~2MB. Consider lazy-loading it only when a page contains Mermaid blocks to keep initial page load fast.
- **`mdex` NIF compilation**: The `mdex` library requires Rust/Cargo to compile. Document this requirement or use a pre-compiled variant if available.

## Testing Strategy

- **Unit tests** for `Docpub.Vault` — use `System.tmp_dir!/0` to create isolated vault directories per test. Verify all CRUD operations, tree building, search, and path safety.
- **Unit tests** for `Docpub.Markdown` — test rendering output, wiki-link conversion, and edge cases (empty input, malformed links, nested formatting).
- **LiveView integration tests** for `VaultLive` — use `Phoenix.LiveViewTest` to simulate navigation, mode toggling, editing, and search. Create a test vault in `ConnCase` setup.
- **Plug tests** for `VaultAuth` — test with auth enabled/disabled, valid/invalid passwords.
- **Controller tests** for `VaultFileController` — test serving various file types, 404 for missing files, path traversal rejection.
- **Manual testing**: Verify Mermaid rendering, responsive layout, and wiki-link navigation in a browser with a real Obsidian vault.

## Open Questions

- [x] Is `mdex` the right markdown library, or would `earmark` be preferred for pure-Elixir simplicity (at the cost of fewer features)?  Answer: use mdex 
- [x] Should file watching (`FileSystem` library) be included in the initial implementation to auto-refresh when vault files change on disk?  Answer: yes use file-watching
- [x] What's the maximum expected vault size? This affects whether upfront file tree loading is viable or if pagination/lazy-loading is needed.  Answer: 1500 files
- [x] Should the escript be a priority for the first iteration, or is a Mix task sufficient for now?  Answer: escript is a priority
- [x] How should image paths in markdown be resolved — relative to the document, relative to the vault root, or both?  Answer: relative to document
