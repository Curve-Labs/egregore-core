# Managing Multiple Repos

Egregore can manage your team's repos alongside the hub. You work from the hub and Egregore handles branching, commits, and PRs across all of them.

## Setup

During setup, add your repos to `egregore.json`:

```json
{
  "org_name": "Acme",
  "github_org": "acme-corp",
  "memory_repo": "https://github.com/acme-corp/acme-corp-memory.git",
  "api_url": "https://egregore-production-55f2.up.railway.app",
  "repos": ["frontend", "backend", "infra"]
}
```

Each repo in `repos` is expected to:
- Exist at `https://github.com/{github_org}/{repo}`
- Be cloned as a sibling directory: `../frontend/`, `../backend/`, etc.
- Have a `develop` branch (Egregore creates one from `main` if missing)

The setup flow (`/setup`) and the `npx create-egregore` installer both clone these repos automatically.

## How it works

### On session start

Egregore fetches all managed repos in parallel and shows their status:

```
  User: alice
  Branch: develop
  Develop: synced
  Memory: synced
  Repos:
    frontend: develop
    backend: dev/alice/auth-flow *
    infra: main
```

The `*` means uncommitted changes.

### Working on a repo

Just say what you're working on. Egregore reads and edits files in the sibling directory.

```
> I need to fix the token refresh logic in the backend

  Looking at ../backend/src/auth/token.ts...
```

All file operations use the sibling path (`../backend/`). You stay in the hub.

### Branching

Same strategy as the hub: `develop` is the integration branch, working branches are topic-based.

```
> /branch auth flow in backend

  Creating branch in backend...
  git -C ../backend checkout -b dev/alice/auth-flow origin/develop
  ✓ Created dev/alice/auth-flow in backend
```

Branch naming follows the same conventions:
- `dev/{author}/{topic-slug}` for general work
- `feature/{slug}` for features
- `bugfix/{slug}` for fixes

### Saving

`/save` scans all repos. If a managed repo has changes, it gets the same treatment as the hub:

1. Ensure on a working branch (creates one from develop if needed)
2. Stage and commit
3. Rebase onto latest develop
4. Push
5. Create PR to develop

```
> /save

  [memory] ✓ Pushed
  [egregore] No changes
  [backend] ✓ Pushed dev/alice/auth-flow → PR #27 to develop
  [frontend] No changes
```

### Release

Each managed repo has its own `develop` → `main` release cycle. The `/release` command works on the hub only. For managed repos, merge PRs to develop through GitHub, then merge develop to main when ready.

## Git workflow summary

```
main ← stable (merge develop when ready)
  develop ← integration (PRs land here)
    dev/{author}/{topic-slug}
```

This is identical across the hub and all managed repos. Every change goes through a PR to develop. No direct pushes to main or develop.

## Adding a repo later

1. Add the repo name to `egregore.json` → `repos[]`
2. Clone it as a sibling: `git clone https://github.com/{org}/{repo}.git ../{repo}`
3. Ensure it has a develop branch: `git -C ../{repo} checkout -b develop && git -C ../{repo} push -u origin develop`

Next session start will pick it up automatically.

## Removing a repo

Remove it from `egregore.json` → `repos[]`. The sibling directory stays — Egregore just stops managing it.
