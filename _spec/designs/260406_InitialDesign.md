# Docpub Initial Design 

## Overview 

Docpub is a Phoenix/Web application that provides a quick way
to share your Obsidian Vault using a Web interface.

Use environment:
- Quick, lightweight sharing 
- Small teams 
- Transient access
- Simple to launch, simple to use

## Comparables 

### CollabMD 

https://github.com/andes90/collabmd 
- written in node 
- a great tool 
- simple to launch

```
|> collabmd --help

  CollabMD — Collaborative Markdown Vault

  Usage:
    collabmd [directory] [options]

  Arguments:
    directory            Path to vault directory (default: current directory)

  Options:
    -p, --port <port>    Port to listen on (default: 1234)
    --host <host>        Host to bind to (default: HOST env var, otherwise 127.0.0.1)
    --auth <strategy>    Auth strategy: none, password, oidc (default: none)
    --auth-password <pw> Password for --auth password (default: generated per run)
    --local-plantuml     Start the bundled docker-compose PlantUML service and use it
    --no-tunnel          Don't start Cloudflare Tunnel
    -v, --version        Show version
    -h, --help           Show this help

  Examples:
    collabmd                        Serve current directory
    collabmd ~/my-vault             Serve a specific vault
    collabmd --port 3000            Use a custom port
    collabmd --auth password        Require a generated password to join
    collabmd --local-plantuml       Use the local docker-compose PlantUML server
    collabmd --no-tunnel            Local only, no tunnel
```

### Others 

- Obsidian Publish - not private - not self-hosted - no editing 
- Obsidian Desktop - nice design - not collaborative
- Quartz - no editing 

## Solution Overview 

I want a solution very similar to CollabMD.

NEED: Search, Sidebar Nav, Links (wiki-style etc.), View/Edit modes, Mermaid
Diagrams, --auth/--auth-password options

DON'T WANT: Chat, AutoTunnel, Diagrams (UML, OIDC), Presence 

Nice but not necessary: Yjs/CRDT - don't expect simultaneous edits

Basics: NO DATABASE - all reads/writes direct to-from the filesystem

FUTURE: AI-CHAT - ask an LLM questions about the vault

## Details 

- The application will be build using Elixir, Phoenix, LiveView 
- There should be an escript to launch the app, with a help page similar to CollabMD
- I don't want side-by-side edit/view - user should be able to toggle between the two modes 
- There should be a command-line option to specify the initial page to view 
- There should be a URL for each document - easy to bookmark 
- Use cookies to remember last visited page

