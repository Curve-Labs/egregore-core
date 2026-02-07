```
  ███████╗ ██████╗ ██████╗ ███████╗ ██████╗  ██████╗ ██████╗ ███████╗
  ██╔════╝██╔════╝ ██╔══██╗██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██╔════╝
  █████╗  ██║  ███╗██████╔╝█████╗  ██║  ███╗██║   ██║██████╔╝█████╗
  ██╔══╝  ██║   ██║██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██╗██╔══╝
  ███████╗╚██████╔╝██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗
  ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝
```

A shared intelligence layer for organizations using Claude Code. Persistent memory, async handoffs, and accumulated knowledge across sessions and people.

## Prerequisites

- [git](https://git-scm.com)
- [jq](https://jqlang.github.io/jq/) — `brew install jq`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — `npm install -g @anthropic-ai/claude-code`

## Install

Download the [latest zip](https://github.com/Curve-Labs/egregore-core/archive/refs/heads/main.zip), unzip, and run:

```bash
cd egregore-core && bash start.sh
```

That's it. The onboarding walks you through everything — GitHub auth, shared memory, knowledge graph connection.

## What happens

1. **Authenticate** — Opens your browser for GitHub authorization (no tokens to copy)
2. **Pick your org** — Choose a GitHub org or personal account
3. **Fork + memory repo** — Creates your org's egregore fork and a shared memory repo
4. **Connected** — Neo4j knowledge graph and Telegram notifications, ready to go

## After setup

From any terminal, just type:

```bash
egregore
```

This syncs everything, puts you on a fresh working branch, and shows you where you are.

### Commands

| Command | What it does |
|---------|-------------|
| `/activity` | See what's happening across your org |
| `/handoff` | Leave notes for others (or future you) |
| `/invite` | Invite someone to your org |
| `/quest` | Start or contribute to an exploration |
| `/ask` | AI-generated questions, routed to self or others |
| `/save` | Commit and push your contributions |

## Invite others

```
/invite <github-username>
```

Adds them as collaborator and sends a zip to the Telegram group. They unzip, run `bash start.sh`, and they're in. After onboarding, they just type `egregore` from anywhere.

## How it works

Egregore gives your team a shared brain that persists across Claude Code sessions:

- **Memory** — Git-based shared knowledge repo (conversations, decisions, patterns)
- **Knowledge graph** — Neo4j for querying across sessions, people, and artifacts
- **Notifications** — Telegram for async handoffs and questions
- **Commands** — Slash commands for common workflows, no git knowledge needed

Built by [Curve Labs](https://curvelabs.eu).
