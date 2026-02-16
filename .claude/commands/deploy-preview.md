Deploy a preview of the marketing site. Pushes to the `preview` branch on egregore-site — Netlify creates a branch deploy at a preview URL. Safe for anyone to run.

## What to do

Run the deploy script with the `--preview` flag. Pass through any additional arguments from $ARGUMENTS.

```bash
bash bin/deploy-site.sh --preview $ARGUMENTS
```

### Format the output

Based on the script's stdout/stderr, show the user a clean summary:

**Normal preview deploy:**
```
Deploying site preview...
  Source: local site/
  Target: Curve-Labs/egregore-site (preview branch)

  {N} files changed
  Pushed ({commit_sha})

Preview URL: https://preview--egregore-site.netlify.app
(Netlify branch deploy — takes ~30s to build)
```

**No changes:**
```
Site is already up to date — nothing to preview.
```

**Dry run:**
```
Dry run — changes that would be deployed to preview:

  Source: local site/
  Target: Curve-Labs/egregore-site (preview branch)

  {diff output from script}

Run /deploy-preview to push these changes.
```

**Error:**
Show the error message from the script. Common issues:
- Missing GITHUB_TOKEN → "Run onboarding first or check your .env"
- site/ directory not found → "The site/ directory doesn't exist"
- Push failed → "Push failed — check your permissions on Curve-Labs/egregore-site"

## Arguments

- `dry` or `--dry-run` — show what would change without pushing
