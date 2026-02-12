# Onboarding Guide

Welcome a new user to this Egregore. Auto-detects what's already set up and skips it.

## Step 1: Read identity

```bash
git config user.name
```

Read `.egregore-state.json` for `github_username`, `github_name`, `usage_type`. Read `egregore.json` for `org_name`.

If `github_username` exists in state, use it. Don't ask for name — we already know.

## Step 2: Show welcome

Display this (personalized with their name and org):

```
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║   ███████╗ ██████╗ ██████╗ ███████╗ ██████╗  ██████╗ ██████╗ ███████╗   ║
║   ██╔════╝██╔════╝ ██╔══██╗██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██╔════╝   ║
║   █████╗  ██║  ███╗██████╔╝█████╗  ██║  ███╗██║   ██║██████╔╝█████╗     ║
║   ██╔══╝  ██║   ██║██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██╗██╔══╝     ║
║   ███████╗╚██████╔╝██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗   ║
║   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝   ║
║                                                                   ║
║                  A Living Organization                            ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
```

Then:

> Welcome to **{org_name}**, {name}!

## Step 3: Create person file (if missing)

Check if `memory/people/{username}.md` exists. If not, create it:

```bash
cat > "memory/people/{username}.md" << 'EOF'
# {github_name or github_username}
Joined: {YYYY-MM-DD}
GitHub: {github_username}
EOF
```

Then commit and push from memory:
```bash
cd memory && git add -A && git commit -m "Add {username}" && git push && cd -
```

If it already exists, skip silently.

## Step 4: Ensure Person node in graph

```bash
RESULT=$(bash bin/graph.sh query "MERGE (p:Person {name: \$name}) RETURN p.name" '{"name":"'"$USERNAME"'"}' 2>/dev/null)
```

Suppress raw output — only show status.

## Step 5: Explain how it works

### What is Egregore?

An **egregore** is a collective thoughtform — an entity that emerges from shared focus and intention. In our case, it's a collaborative intelligence system where humans and AI work together with persistent memory.

### How It Works

**You are not alone here.** Everything you do gets remembered:

1. **Sessions** — Your work gets logged. When you research, code, or explore, it becomes part of the collective memory.

2. **Artifacts** — Findings, decisions, sources, thoughts. Use `/add` to capture anything important.

3. **Handoffs** — When you're done, use `/handoff` to leave notes for others (or future you). They'll be notified.

4. **Quests** — Ongoing explorations that span multiple sessions. Track progress with `/quest`.

### The Flow

```
You work → Sessions logged → /handoff when done
                ↓
        Others pick up → Build on your work
                ↓
        Knowledge accumulates → Egregore grows
```

**You're not using a chatbot. You're working with a system that remembers.**

## Step 6: Offer tutorial

Ask via AskUserQuestion:

```
header: "Next"
question: "Want to take a quick interactive tour?"
options:
  - label: "Yes, run /tutorial"
    description: "5 minute walkthrough of the core loop"
  - label: "Skip for now"
    description: "Jump straight in — you can run /tutorial anytime"
```

If yes → invoke `/tutorial`.
If skip → say "You're all set. Type `/activity` to see what's happening, or just start working."
