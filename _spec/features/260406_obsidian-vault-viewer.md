# Obsidian Vault Viewer

## Summary

Docpub serves an Obsidian vault over the web using Phoenix LiveView, allowing
users to browse, search, and edit markdown documents through a browser. The
application reads and writes directly to the filesystem (no database) and is
launched via an escript with CLI options similar to CollabMD.

## Goals

- Provide a lightweight, self-hosted web interface for sharing and editing an Obsidian vault
- Support small teams with transient access needs
- Be simple to launch and simple to use
- Work well on both desktop and mobile devices

## Non-Goals

- Chat functionality
- Auto-tunneling (e.g., Cloudflare Tunnel)
- UML/PlantUML diagram rendering
- OIDC authentication
- Presence indicators
- Real-time collaborative editing (Yjs/CRDT)

## User Stories

1. **Launch the app**: As a user, I can launch docpub from the command line pointing at my Obsidian vault directory, with options for port, host, auth strategy, and initial page.
2. **Browse documents**: As a user, I can see a sidebar navigation tree reflecting the vault's folder/file structure and click to navigate between documents.
3. **View a document**: As a user, I can view a rendered markdown document with support for wiki-style links (`[[page]]`), standard markdown links, and Mermaid diagrams.
4. **Edit a document**: As a user, I can toggle between view and edit mode on any document, editing the raw markdown which is saved directly to the filesystem.
5. **Search the vault**: As a user, I can search across all documents in the vault by keyword and navigate to results.
6. **Bookmark pages**: As a user, I get a unique URL for each document so I can bookmark or share links directly.
7. **Resume where I left off**: As a user, my last visited page is remembered via cookies so I return to it on my next visit.
8. **Password protection**: As a user, I can launch with `--auth password` and optionally `--auth-password <pw>` to require a password for access.
9. **Mobile access**: As a user, I can use the application on my phone with a responsive layout that adapts to small screens.

## Functional Requirements

### CLI / Escript

- Escript entry point that accepts a vault directory path (defaults to current directory)
- Options: `--port`, `--host`, `--auth` (none | password), `--auth-password`, `--initial-page`, `--help`, `--version`
- Generated password per run when `--auth password` is used without `--auth-password`
- Help page printed on `--help` showing usage, arguments, options, and examples

### Sidebar Navigation

- Tree view reflecting the vault's directory structure
- Folders are collapsible
- Current document is highlighted
- Responsive: collapses to a toggle/drawer on mobile

### Document Viewing

- Render markdown to HTML
- Support Obsidian wiki-style links (`[[Page Name]]`, `[[folder/Page Name]]`, `[[Page Name|Display Text]]`)
- Support standard markdown links
- Render Mermaid diagram fenced code blocks
- Syntax highlighting for code blocks

### Document Editing

- Toggle button to switch between view and edit mode (not side-by-side)
- Plain textarea or code editor for raw markdown
- Save writes directly to the filesystem
- Unsaved changes warning before navigation

### Search

- Full-text search across all vault documents
- Results show document title and matching snippet
- Click result to navigate to that document

### Authentication

- No auth by default
- Password auth via session cookie when `--auth password` is set
- Simple login page prompting for password

### State & Persistence

- No database; all document reads/writes go directly to the filesystem
- Last visited page stored in a browser cookie
- URL-per-document for bookmarking

## UI/UX Requirements

- Responsive layout: works on desktop and mobile
- Clean, minimal design with good typography and spacing
- Smooth transitions between view and edit modes
- Loading indicator (topbar) during navigation
- Sidebar drawer on mobile with toggle button

## Open Questions

- Should the sidebar show only `.md` files or also other file types (images, PDFs)?  Answer: also show PDFs and images
- What should happen when a wiki-link target doesn't exist — show a "create page" prompt or a 404-style message?  Answer: show a 404
- Should there be a way to create new documents from the UI, or only edit existing ones?  Answer: yes, allow create,update and delete
- How should large vaults perform — lazy-load the file tree or load it all upfront?  Answer: I think load everything up front 
