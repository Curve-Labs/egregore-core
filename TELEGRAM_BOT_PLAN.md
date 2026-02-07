# Telegram Bot for Curve Labs Activity - Implementation Plan

## Overview

Create a Telegram bot that responds to "@bot What's happening" in group chats and provides Curve Labs activity data (recent commits, handoffs, decisions, findings) just like the `/activity` command.

**Architecture:** Two-service design with webhook pattern - BOTH deployed on Railway
- **Activity API Server** - Clones Curve Labs repos from GitHub, runs git commands, exposes activity via HTTP
- **Telegram Bot** - Calls API webhook, formats and sends responses to Telegram

## Technology Stack

- **Both services:** Python 3.11+
- **API Server:** FastAPI + Uvicorn
- **Bot:** python-telegram-bot library
- **Deployment:** Railway for both services (API + Bot)
- **Repo Location:** Both services live in `egregore/` repository

## Critical Files to Reference

- `skills/cl-collaborator/SKILL.md` (lines 541-650) - Original `/activity` implementation logic
- `memory/conversations/index.md` - Handoffs data structure
- `memory/knowledge/{decisions,findings,patterns}/` - Knowledge base structure

## Implementation Steps

### Phase 1: Activity API Server

Create in `egregore/activity-api/`

#### 1.1 Project Structure
```
egregore/
└── activity-api/
    ├── .env.example
    ├── .gitignore
    ├── requirements.txt
    ├── README.md
    ├── Dockerfile          # For Railway deployment
    ├── railway.json        # Railway config
    ├── startup.sh          # Clone repos on first run
    ├── app/
    │   ├── __init__.py
    │   ├── main.py         # FastAPI app
    │   ├── config.py       # Environment config
    │   ├── auth.py         # Bearer token validation
    │   ├── models.py       # Pydantic models
    │   └── collectors/
    │       ├── __init__.py
    │       ├── memory.py   # Parse memory/ files
    │       ├── git.py      # Git commands
    │       └── github.py   # gh CLI for PRs
    └── tests/
        ├── test_collectors.py
        └── test_api.py
```

#### 1.2 Core Files to Implement

**requirements.txt**
```
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic==2.5.3
pydantic-settings==2.1.0
python-dotenv==1.0.0
gitpython==3.1.40
```

**app/models.py** - Define JSON schema (Pydantic models):
- `ActivityResponse` - Top-level response
- `Handoff`, `Decision`, `Finding`, `Pattern` - Memory items
- `GitCommit`, `PullRequest`, `ProjectGitActivity` - Git data

**app/config.py** - Configuration with Railway defaults:
```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    API_TOKEN: str
    PORT: int = 8000
    REPOS_BASE_PATH: str = "/app/repos"  # Default for Railway
    GITHUB_TOKEN: str = ""  # Optional for gh CLI

    class Config:
        env_file = ".env"

settings = Settings()
```

**app/collectors/memory.py** - Read Curve Labs memory:
- `collect_handoffs()` - Parse `memory/conversations/index.md` markdown table from `/app/repos/curve-labs-memory/conversations/index.md`
- `collect_knowledge(category)` - Scan `memory/knowledge/{category}/` for recent .md files
- Extract date from filename pattern `YYYY-MM-DD-title.md`
- Use `settings.REPOS_BASE_PATH` to locate repos

**app/collectors/git.py** - Run git commands:
- `collect_git_commits(repo_path, days=7)` - Run `git log --oneline --since="{days} days ago" --all --format="%h %s (%an, %ar)"`
- `collect_active_branches(repo_path)` - Run `git branch -r --list 'origin/feature/*' --list 'origin/bugfix/*'`
- Use `asyncio.create_subprocess_exec()` for async execution

**app/collectors/github.py** - Fetch PRs:
- `collect_open_prs(repo_name)` - Run `gh pr list --repo Curve-Labs/{repo} --state open --json number,title,author,createdAt,url`
- Handle case where gh CLI not available (return empty list)

**app/main.py** - FastAPI endpoints:
```python
@app.get("/health")
async def health_check():
    # Check memory accessible, git available

@app.get("/activity", response_model=ActivityResponse)
async def get_activity(
    days: int = 7,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    verify_token(credentials.credentials)
    # Collect all data
    # Return ActivityResponse
```

**app/auth.py** - Simple bearer token validation:
```python
def verify_token(token: str):
    if token != settings.API_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid token")
```

**startup.sh** - Clone Curve Labs repos on Railway startup:
```bash
#!/bin/bash
set -e

REPOS_DIR="/app/repos"
mkdir -p $REPOS_DIR

# Clone repos if they don't exist
if [ ! -d "$REPOS_DIR/curve-labs-memory" ]; then
    echo "Cloning curve-labs-memory..."
    git clone https://github.com/Curve-Labs/curve-labs-memory.git $REPOS_DIR/curve-labs-memory
fi

if [ ! -d "$REPOS_DIR/tristero" ]; then
    echo "Cloning tristero..."
    git clone https://github.com/Curve-Labs/tristero.git $REPOS_DIR/tristero
fi

if [ ! -d "$REPOS_DIR/lace" ]; then
    echo "Cloning lace..."
    git clone https://github.com/Curve-Labs/lace.git $REPOS_DIR/lace || echo "Lace clone failed (might not exist yet)"
fi

# Pull latest changes
echo "Pulling latest changes..."
cd $REPOS_DIR/curve-labs-memory && git pull origin main || true
cd $REPOS_DIR/tristero && git pull origin main || true
cd $REPOS_DIR/lace && git pull origin main || true

echo "Repos ready!"
cd /app

# Start the API server
exec uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

**Dockerfile** - For Railway deployment:
```dockerfile
FROM python:3.11-slim

# Install git and gh CLI
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/
COPY startup.sh .
RUN chmod +x startup.sh

# Expose port
EXPOSE 8000

# Run startup script (clones repos, then starts server)
CMD ["./startup.sh"]
```

**railway.json** - Railway configuration:
```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "DOCKERFILE",
    "dockerfilePath": "Dockerfile"
  },
  "deploy": {
    "numReplicas": 1,
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 10
  }
}
```

#### 1.3 Environment Variables (Railway Dashboard)
```
API_TOKEN=generate-random-uuid-here
PORT=8000
GITHUB_TOKEN=optional-for-private-repos-and-pr-fetching
```

### Phase 2: Telegram Bot

Create in `egregore/telegram-bot/`

#### 2.1 Project Structure
```
egregore/
└── telegram-bot/
    ├── .env.example
    ├── .gitignore
    ├── requirements.txt
    ├── README.md
    ├── Dockerfile
    ├── railway.json
    ├── bot/
    │   ├── __init__.py
    │   ├── main.py         # Bot entry point
    │   ├── config.py       # Environment config
    │   ├── handlers.py     # Message handlers
    │   ├── formatter.py    # Format JSON to Telegram message
    │   └── api_client.py   # HTTP client for Activity API
    └── tests/
        └── test_handlers.py
```

#### 2.2 Core Files to Implement

**requirements.txt**
```
python-telegram-bot==20.7
httpx==0.26.0
pydantic==2.5.3
python-dotenv==1.0.0
```

**bot/handlers.py** - Handle Telegram messages:
```python
async def activity_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    # Check if bot was mentioned
    # Check if message contains "what's happening" (case-insensitive)
    # Show typing indicator
    # Call API to fetch activity
    # Format and send response
```

**bot/api_client.py** - Call Activity API:
```python
async def fetch_activity(days: int = 7) -> ActivityResponse:
    async with httpx.AsyncClient() as client:
        response = await client.get(
            f"{settings.ACTIVITY_API_URL}/activity",
            headers={"Authorization": f"Bearer {settings.API_TOKEN}"},
            params={"days": days},
            timeout=30.0
        )
        return ActivityResponse(**response.json())
```

**bot/formatter.py** - Format activity as Telegram message:
- Use Telegram Markdown formatting
- Emojis for sections: 📝 Handoffs, ⚖️ Decisions, 💡 Findings, 💻 Commits, 🌿 Branches, 🔀 PRs
- Limit items to avoid message length limits (Telegram max ~4096 chars)
- Format similar to `/activity` output but adapted for mobile viewing

**bot/main.py** - Bot startup:
```python
def main():
    application = Application.builder().token(settings.TELEGRAM_BOT_TOKEN).build()

    # Handler for mentioned messages with "what's happening"
    application.add_handler(MessageHandler(
        filters.TEXT & filters.Entity("mention") & filters.Regex(r"(?i)what'?s?\s+happening"),
        activity_handler
    ))

    # Run webhook for Railway
    application.run_webhook(
        listen="0.0.0.0",
        port=settings.PORT,
        url_path=settings.WEBHOOK_PATH,
        webhook_url=f"{settings.WEBHOOK_URL}{settings.WEBHOOK_PATH}"
    )
```

#### 2.3 Dockerfile for Railway
```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY bot/ ./bot/

CMD ["python", "-m", "bot.main"]
```

#### 2.4 railway.json
```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "DOCKERFILE",
    "dockerfilePath": "Dockerfile"
  },
  "deploy": {
    "numReplicas": 1,
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 10
  }
}
```

#### 2.5 Environment Variables (.env)
```
TELEGRAM_BOT_TOKEN=get-from-botfather
ACTIVITY_API_URL=https://your-ngrok-or-server-url.com
API_TOKEN=same-as-api-server
WEBHOOK_URL=https://your-app.railway.app
WEBHOOK_PATH=/webhook
PORT=8080
```

### Phase 3: Railway Deployment (Both Services)

#### 3.1 Prerequisites
1. **Create Telegram Bot**
   - Message @BotFather on Telegram
   - Create new bot: `/newbot`
   - Choose name (e.g., "Curve Labs Activity Bot") and username
   - Copy bot token

2. **Generate API Token**
   ```bash
   # Generate a secure random token
   python -c "import uuid; print(uuid.uuid4())"
   ```
   Save this token - you'll use it for both services

3. **Push to GitHub**
   - Commit `activity-api/` and `telegram-bot/` directories to egregore
   - Push to GitHub

#### 3.2 Deploy Activity API to Railway

1. **Create New Railway Project**
   - Go to https://railway.app
   - Click "New Project" → "Deploy from GitHub repo"
   - Select `egregore` repository
   - Choose "Add Service" → select the repo

2. **Configure Root Directory**
   - In service settings, set **Root Directory** to `activity-api`
   - This tells Railway to build from that subdirectory

3. **Add Environment Variables**
   In the Railway dashboard, add:
   ```
   API_TOKEN=<your-generated-uuid>
   PORT=8000
   GITHUB_TOKEN=<optional-for-private-repos>
   ```

4. **Deploy**
   - Railway will automatically build from the Dockerfile
   - Wait for deployment to complete
   - Copy the service URL (e.g., `https://activity-api-production-xxxx.railway.app`)

5. **Test API Health**
   ```bash
   curl https://activity-api-production-xxxx.railway.app/health
   ```

#### 3.3 Deploy Telegram Bot to Railway

1. **Add Another Service**
   - In the same Railway project, click "New Service"
   - Select the same GitHub repo (`egregore`)

2. **Configure Root Directory**
   - Set **Root Directory** to `telegram-bot`

3. **Add Environment Variables**
   In the Railway dashboard, add:
   ```
   TELEGRAM_BOT_TOKEN=<from-botfather>
   ACTIVITY_API_URL=https://activity-api-production-xxxx.railway.app
   API_TOKEN=<same-uuid-as-api>
   WEBHOOK_PATH=/webhook
   PORT=8080
   ```

   **Note:** Leave `WEBHOOK_URL` empty for now - we'll add it after deployment

4. **Deploy**
   - Railway will build and deploy
   - Once deployed, copy the bot service URL (e.g., `https://telegram-bot-production-yyyy.railway.app`)

5. **Update WEBHOOK_URL Environment Variable**
   - Go back to bot service environment variables
   - Add: `WEBHOOK_URL=https://telegram-bot-production-yyyy.railway.app`
   - Redeploy (or it will auto-redeploy)

6. **Set Telegram Webhook**
   ```bash
   curl -X POST "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/setWebhook" \
        -d "url=https://telegram-bot-production-yyyy.railway.app/webhook"
   ```

   You should get response: `{"ok":true, "result":true}`

#### 3.4 Verify Deployment
1. Add bot to a Telegram group
2. Send message: `@yourbotname What's happening`
3. Bot should respond with Curve Labs activity data

#### 3.5 Auto-Deploy on Git Push (Optional)
Railway will automatically redeploy when you push to GitHub. No additional configuration needed!

### Phase 4: Testing

#### 4.1 Test Activity API
```bash
# Test health endpoint
curl http://localhost:8000/health

# Test activity endpoint
curl -H "Authorization: Bearer your-token" \
     http://localhost:8000/activity?days=7
```

#### 4.2 Test Telegram Bot
1. Add bot to test group
2. Send message: "@yourbotname What's happening"
3. Verify bot responds with activity data
4. Test error handling: Stop API server, verify bot shows error message

#### 4.3 End-to-End Test
- Ensure API can read memory/ and run git commands
- Verify JSON response structure matches models
- Confirm Telegram formatting is readable on mobile
- Check response time < 10 seconds

## Data Flow (Railway Deployment)

```
User in Telegram Group
  → "@bot What's happening"
    ↓
Telegram Server
  → Sends webhook POST to Railway Bot Service
    ↓
Railway: Telegram Bot Service (telegram-bot-production-yyyy.railway.app)
  → Bot handler checks mention + regex match
  → Calls GET https://activity-api-production-xxxx.railway.app/activity
  → Header: Authorization: Bearer <API_TOKEN>
    ↓
Railway: Activity API Service (activity-api-production-xxxx.railway.app)
  → Validates Bearer token
  → Reads from /app/repos/curve-labs-memory/conversations/index.md
  → Scans /app/repos/curve-labs-memory/knowledge/{decisions,findings,patterns}/
  → Runs git log on /app/repos/tristero
  → Runs git log on /app/repos/lace
  → Runs git branch -r for active branches
  → Runs gh pr list for open PRs (if GITHUB_TOKEN set)
  → Returns ActivityResponse JSON
    ↓
Railway: Telegram Bot Service
  → Receives JSON response
  → Formats as Telegram message (markdown + emojis)
  → Sends reply via Telegram Bot API
    ↓
User sees formatted activity in Telegram
```

**Railway Network Flow:**
- Both services run on Railway in the same project
- Bot calls API via public HTTPS URL (fast within Railway network)
- Repos cloned from GitHub on API service startup
- No local machine required - fully cloud-based

**Repo Update Strategy:**
- Repos are cloned fresh on each Railway deployment
- To get latest changes: Redeploy the Activity API service
- Future enhancement: Add `/refresh` endpoint to pull latest without redeploying

## Error Handling

**API Server:**
- Missing memory path → return empty arrays, log error
- Git command fails → skip repo, add to errors array
- gh CLI unavailable → skip PRs
- Never crash, always return 200 with partial data + errors list

**Telegram Bot:**
- API unreachable → reply "Activity API is currently unavailable. Please try again later."
- API returns errors → display available data, mention issues at bottom
- Timeout (30s) → inform user to retry
- Invalid token → log error, send generic error message

## Security

1. **API Token:** Generate strong random token (UUID), store in env vars
2. **Input Validation:** Validate `days` parameter (1-30 range)
3. **Path Safety:** Never use user input in file paths, hardcode repos list
4. **Command Injection:** Always use subprocess with list args, never `shell=True`
5. **HTTPS Only:** Require HTTPS for webhook and API (ngrok provides this)

## Performance

- **Caching:** Consider caching activity data for 1-2 minutes
- **Parallel Execution:** Run git commands for different repos in parallel with `asyncio.gather()`
- **Timeouts:** git: 10s, gh: 15s, total API request: 30s
- **Rate Limiting:** Limit bot responses to once per minute per chat

## Monitoring

- Log all API requests with response times
- Log Telegram messages received and responses sent
- Track errors (git failures, memory read failures)
- Monitor Railway metrics (CPU, memory, request count)

## Future Enhancements

**Phase 1 (Quick Wins):**
1. Add `/refresh` endpoint to API - pulls latest from GitHub without redeploying
2. Add `/health` check to bot that pings API
3. Project filtering: "@bot what's happening in tristero"
4. Time range: "@bot activity yesterday" or "@bot activity this week"

**Phase 2 (User Experience):**
5. User filtering: "@bot show PRs by oz"
6. Interactive Telegram buttons for pagination/filtering
7. Scheduled updates: Daily digest sent to channel
8. Direct message support (not just groups)

**Phase 3 (Advanced):**
9. Proactive notifications when new handoffs created
10. GitHub webhook integration - instant updates instead of redeploying
11. Support multiple Curve Labs workspaces
12. Web dashboard showing same data
13. Slack/Discord bot using same API

## Verification Checklist

After implementation, verify:

- [ ] API server starts and serves /health endpoint
- [ ] API can read memory/conversations/index.md
- [ ] API can parse handoffs table correctly
- [ ] API can scan knowledge directories
- [ ] API can run git log on tristero
- [ ] API returns valid JSON matching ActivityResponse schema
- [ ] Bot connects to Telegram
- [ ] Bot responds to @mention + "what's happening"
- [ ] Bot ignores messages without mention
- [ ] Bot calls API with correct auth header
- [ ] Bot formats response with emojis and markdown
- [ ] Bot handles API errors gracefully
- [ ] Railway deployment succeeds
- [ ] Webhook is set correctly on Telegram
- [ ] End-to-end test: Message in group → bot responds with activity

## Railway Deployment Notes

**Cost Estimate (5-person team):**
- Railway free tier: $5/month in credits
- Expected usage: ~$2-5/month for both services
- Very light usage - services mostly idle
- API only runs when bot calls it (5-20 times/day)
- Bot only wakes for Telegram messages

**Repo Synchronization:**
- Repos cloned from GitHub on Railway startup
- Get latest: Redeploy the API service in Railway dashboard
- Alternative: Add webhook from GitHub to Railway for auto-redeploy
- Future: Add `/refresh` endpoint to git pull without redeploying

**Private Repos:**
- If Curve Labs repos are private, add `GITHUB_TOKEN` to API service
- Generate token at https://github.com/settings/tokens
- Needs `repo` scope for cloning private repos

**Railway Project Structure:**
```
Railway Project: curve-labs-activity-bot
├── Service 1: activity-api (root: activity-api/)
│   └── URL: https://activity-api-production-xxxx.railway.app
└── Service 2: telegram-bot (root: telegram-bot/)
    └── URL: https://telegram-bot-production-yyyy.railway.app
```

**Shared Code:**
- `app/models.py` is duplicated in both services (simpler than git submodules)
- Keep them in sync manually when updating JSON schema
- Alternative: Create a shared Python package later

**Monitoring:**
- Use Railway logs tab to view API requests and bot messages
- Check Railway metrics for CPU/memory usage
- Set up Railway alerts for deployment failures

## Notes

- Keep bot lightweight - all business logic in API
- API can be extended later for web dashboard, Slack bot, Discord bot, etc.
- Consider using Redis for caching if team grows and API becomes slow
- Railway handles HTTPS/SSL automatically - no nginx needed

## Troubleshooting (Railway Deployment)

**Bot not responding:**
1. Check Railway logs for telegram-bot service
2. Verify webhook is set: `curl https://api.telegram.org/bot<TOKEN>/getWebhookInfo`
3. Check WEBHOOK_URL environment variable matches deployed URL
4. Ensure bot is added to group and has message permissions

**API errors:**
1. Check Railway logs for activity-api service
2. Verify repos cloned successfully (check startup.sh logs)
3. Test health endpoint: `curl https://activity-api-xxx.railway.app/health`
4. Check API_TOKEN matches between services

**Git clone fails:**
1. If repos are private, add GITHUB_TOKEN to environment variables
2. Check token has `repo` scope
3. Verify repo URLs in startup.sh are correct

**Empty activity data:**
1. Check repos exist in /app/repos on API service
2. Verify memory/conversations/index.md exists
3. Run `git log` to ensure repos have commits
4. Check Railway logs for file read errors

**Deployment fails:**
1. Check Dockerfile syntax
2. Verify requirements.txt has all dependencies
3. Check Railway build logs for Python errors
4. Ensure startup.sh has execute permissions (chmod +x)

## Estimated Scope

- **Activity API Server:** ~400-500 lines (collectors + startup script)
- **Telegram Bot:** ~150-200 lines (handlers + formatting)
- **Configuration:** Dockerfile, railway.json, startup.sh for both services
- **Total implementation time:** 5-7 hours for experienced developer
- **Deployment time:** 30-60 minutes once code is ready
