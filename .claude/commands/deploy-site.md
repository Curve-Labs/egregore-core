Deploy the marketing site from `Curve-Labs/egregore` → `Curve-Labs/egregore-site` (auto-deploys to egregore.xyz via Netlify).

## What to do

Run the deploy script and show formatted output. Pass through any arguments from $ARGUMENTS (e.g. `dry`, `--source-branch feature/new-hero`).

```bash
bash bin/deploy-site.sh $ARGUMENTS
```

### Format the output

Based on the script's stdout/stderr, show the user a clean summary:

**Normal deploy:**
```
Deploying site to egregore.xyz...
  Source: Curve-Labs/egregore (main) → site 2/
  Target: Curve-Labs/egregore-site (main)

  {N} files changed
  Pushed ({commit_sha})

Netlify will auto-deploy in ~30s.
```

**No changes:**
```
Site is already up to date — nothing to deploy.
```

**Dry run:**
```
Dry run — changes that would be deployed:

  Source: Curve-Labs/egregore (main) → site 2/
  Target: Curve-Labs/egregore-site (main)

  {diff output from script}

Run /deploy-site to push these changes.
```

**Error:**
Show the error message from the script. Common issues:
- Missing GITHUB_TOKEN → "Run onboarding first or check your .env"
- Source directory not found → "The 'site 2/' directory doesn't exist in the source repo"
- Push failed → "Push failed — check your permissions on Curve-Labs/egregore-site"

## Arguments

- `dry` or `--dry-run` — show what would change without pushing
- `--source-branch <branch>` — deploy from a different branch (default: main)
