# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docpub is a Phoenix 1.8 + LiveView web application (Elixir ~> 1.15). No database (Ecto not included). Uses Bandit as the HTTP adapter.

## Commands

- `mix setup` - install deps and build assets
- `mix phx.server` or `iex -S mix phx.server` - start dev server (localhost:4000)
- `mix test` - run all tests
- `mix test test/path/to/test.exs` - run a single test file
- `mix test --failed` - re-run previously failed tests
- `mix format` - format code
- `mix precommit` - compile (warnings-as-errors), clean unused deps, format, and test. **Run before committing.**

## Tech Stack

- **Backend**: Phoenix 1.8.5, Phoenix LiveView 1.1.0, Elixir
- **Frontend**: Tailwind CSS v4, esbuild, daisyUI themes, Heroicons
- **HTTP client**: Req (never use httpoison, tesla, or httpc)
- **Email**: Swoosh
- **Testing**: ExUnit, Phoenix.LiveViewTest, LazyHTML

## Architecture

Standard Phoenix structure. Key paths:

- `lib/docpub_web/router.ex` - route definitions
- `lib/docpub_web/components/core_components.ex` - shared UI components (`<.input>`, `<.icon>`, etc.)
- `lib/docpub_web/components/layouts.ex` - layout components (owns `<.flash_group>`)
- `lib/docpub_web.ex` - web module macros (html_helpers, aliases)
- `config/` - env-specific configuration (dev on 4000, test on 4002)
- `assets/js/app.js` and `assets/css/app.css` - single JS/CSS entry points
- `_spec/` - design documents, feature specs, and implementation plans

## Critical Conventions (from AGENTS.md and RULES.md)

These are enforced rules, not suggestions. The full details live in `AGENTS.md`.

### Phoenix/LiveView
- Always wrap LiveView templates with `<Layouts.app flash={@flash} ...>`
- Always use `<.form for={@form}>` with `to_form/2`; never pass changesets to templates
- Always use `<.input>` from core_components for form inputs
- Always use `<.icon name="hero-...">` for icons
- Always use LiveView streams for collections (never assign raw lists)
- Never use deprecated `live_redirect`/`live_patch`; use `<.link navigate={}>` / `push_navigate`
- Never call `<.flash_group>` outside of `layouts.ex`

### Templates (HEEx)
- Use `{...}` for interpolation in attributes and values; `<%= %>` only for block constructs (if/cond/case/for)
- Use `cond` or `case` for multiple conditionals (Elixir has no elsif)
- Class attributes must use list syntax: `class={["base", @flag && "extra"]}`
- Use `phx-no-curly-interpolation` on tags containing literal curly braces

### JavaScript/CSS
- Never write inline `<script>` tags; use colocated hooks with `:type={Phoenix.LiveView.ColocatedHook}`
- Colocated hook names must start with `.` (e.g., `.PhoneNumber`)
- Never use `@apply` in CSS; use Tailwind classes directly
- Only `app.js` and `app.css` bundles are supported; import vendor deps into them

### Elixir
- No index-based list access; use `Enum.at/2` or pattern matching
- Rebind block expression results to variables (if/case/cond don't implicitly return in the outer scope)
- Never nest multiple modules in one file
- Use dot notation on structs, not map access syntax
- Use `Task.async_stream` for concurrent work with back-pressure

### Testing
- Use `start_supervised!/1` for process cleanup
- Use `Process.monitor/1` + `assert_receive` instead of `Process.sleep/1`
- Test element presence via DOM IDs, not text content
- Use `element/2`, `has_element/2` from Phoenix.LiveViewTest
