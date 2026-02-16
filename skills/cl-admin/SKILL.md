# Curve Labs Admin

This repo (curve-labs-core) is the development repo for Egregore. From here, we build and ship to egregore-core — the public distribution that all Egregore users run.

## How it works

```
curve-labs-core   ← You are here. Development happens here.
    │
    │  /sync-public
    ▼
egregore-core     ← Public repo. Users clone this. Deployed via /release.
```

**Everything in this repo ships to egregore-core** except:
- `skills/cl-admin/` (this skill — Curve Labs internal only)
- `api/`, `telegram-bot/`, `tests/`, `blog/`, `packages/`, `data/` (server-side / infra)
- Personal state (`.env`, `.egregore-state.json`, `egregore.json`, `memory/`)

When you change commands, scripts, CLAUDE.md, or bin/ — those changes reach every Egregore user after `/release` + `/sync-public`.

## Admin commands

These commands only exist in curve-labs-core:

- `/release` — Merge develop to main, tag, sync to egregore-core, notify team
- `/sync-public` — Rsync curve-labs-core to egregore-core (one-way)

## Mindset

We are Egregore users too. Every workflow we build, we use ourselves first. If something is annoying or breaks for us, it will break for users. Fix it here, ship it to everyone.

The git abstraction should be invisible. Users should never see a checkout, a rebase conflict, or a stash. If they do, the abstraction leaked.
