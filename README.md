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
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — `npm install -g @anthropic-ai/claude-code`

## Setup

```bash
npx create-egregore@latest --local
```

Signs in with GitHub, creates repos under your org, sets up shared memory, and configures everything locally. No server or account needed.

### Join an existing team

Got invited? Run:

```bash
npx create-egregore@latest join <org>/<repo>
```

Signs in with GitHub, accepts the invitation, clones the team's repos, and sets up your workspace.

## After setup

Egregore adds a shell alias to your profile. From any terminal:

```bash
egregore
```

This opens Claude Code in your egregore directory, syncs everything, and shows you where you are.

Some commands to get started:

| Command | What it does |
|---------|-------------|
| `/activity` | See what's happening across your org |
| `/handoff` | Leave notes for others (or future you) |
| `/invite` | Invite someone to your org |
| `/save` | Commit and push your contributions |

## Invite others

```
/invite <github-username>
```

Adds them as a collaborator on your repos. Tell them to run:

```
npx create-egregore@latest join <your-org>/<repo>
```

## Upgrade to managed

Local mode works entirely on the filesystem. To enable the knowledge graph, Telegram notifications, and dashboard:

```
/connect
```

## How it works

Egregore gives your team a shared brain that persists across Claude Code sessions:

- **Memory** — Git-based shared knowledge repo (decisions, patterns, handoffs)
- **Local mode** — Works fully offline with filesystem-based memory
- **Knowledge graph** — Optional: query across sessions, people, and artifacts
- **Notifications** — Optional: Telegram for async handoffs and questions
- **Commands** — Slash commands for common workflows, no git knowledge needed
- **Repos** — Managed repos are cloned alongside your instance for shared context

Built by [Curve Labs](https://curvelabs.eu).
