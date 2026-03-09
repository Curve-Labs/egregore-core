terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

provider "coder" {}
provider "docker" {
  registry_auth {
    address  = "ghcr.io"
    username = "oauth2"
    password = var.ghcr_token
  }
}

# ─── Template parameters (set per org by admin) ──────────────────

data "coder_parameter" "org_slug" {
  name         = "org_slug"
  display_name = "Org Slug"
  description  = "The Egregore org identifier"
  type         = "string"
  mutable      = false
}

data "coder_parameter" "org_name" {
  name         = "org_name"
  display_name = "Org Name"
  description  = "Display name for the org"
  type         = "string"
  mutable      = false
}

data "coder_parameter" "github_org" {
  name         = "github_org"
  display_name = "GitHub Org"
  description  = "GitHub org or user that owns the repos"
  type         = "string"
  mutable      = false
}

data "coder_parameter" "repo_name" {
  name         = "repo_name"
  display_name = "Repo Name"
  description  = "Name of the Egregore repo (fork)"
  type         = "string"
  default      = "egregore-core"
  mutable      = false
}

data "coder_parameter" "managed_repos" {
  name         = "managed_repos"
  display_name = "Managed Repos"
  description  = "Comma-separated list of managed repos"
  type         = "string"
  default      = ""
  mutable      = false
}

# ─── Workspace metadata ──────────────────────────────────────────
# Note: Anthropic API key is NOT a Coder parameter. Users set their key
# via egregore.xyz/settings, and workspace-init.sh fetches it from the API.

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# ─── Org-level secrets (set by admin in Coder template variables) ─

variable "egregore_api_key" {
  type      = string
  sensitive = true
}

variable "api_url" {
  type    = string
  default = "https://egregore-production-55f2.up.railway.app"
}

variable "memory_url" {
  type = string
}

variable "fork_url" {
  type = string
}

variable "ghcr_token" {
  type      = string
  sensitive = true
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "Org-level GitHub token for git operations (clone, push)"
}

# ─── Docker image ────────────────────────────────────────────────

resource "docker_image" "egregore" {
  name         = "ghcr.io/curve-labs/egregore-workspace:latest"
  keep_locally = true
}

# ─── Container ───────────────────────────────────────────────────

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  image = docker_image.egregore.image_id

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    # Org-level GitHub token for git clone/push (all users share this for repo access)
    "GITHUB_TOKEN=${var.github_token}",
    # Org-level API key for Egregore API (Neo4j, notifications, etc.)
    "EGREGORE_API_KEY=${var.egregore_api_key}",
    # Coder workspace owner info (for git identity + Anthropic key lookup)
    "CODER_USERNAME=${data.coder_workspace_owner.me.name}",
    # Org config
    "ORG_SLUG=${data.coder_parameter.org_slug.value}",
    "ORG_NAME=${data.coder_parameter.org_name.value}",
    "GITHUB_ORG=${data.coder_parameter.github_org.value}",
    "REPO_NAME=${data.coder_parameter.repo_name.value}",
    "MANAGED_REPOS=${data.coder_parameter.managed_repos.value}",
    "API_URL=${var.api_url}",
    "MEMORY_URL=${var.memory_url}",
    "FORK_URL=${var.fork_url}",
  ]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # Persistent home directory across workspace restarts
  volumes {
    volume_name    = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-home"
    container_path = "/home/egregore"
    read_only      = false
  }

  user = "egregore"

  # Run Coder agent init script (downloads + starts the agent)
  command = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
}

# ─── Coder agent ─────────────────────────────────────────────────

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/home/egregore/egregore"

  display_apps {
    vscode       = false
    web_terminal = true
    ssh_helper   = true
  }

  startup_script          = "/opt/egregore/bin/workspace-init.sh"
  startup_script_behavior = "blocking"

  metadata {
    key          = "org"
    display_name = "Egregore"
    script       = "jq -r '.org_name' ~/egregore/egregore.json 2>/dev/null || echo 'initializing...'"
    interval     = 30
  }

  metadata {
    key          = "branch"
    display_name = "Branch"
    script       = "cd ~/egregore && git branch --show-current 2>/dev/null || echo '-'"
    interval     = 10
  }
}

# ─── Web terminal app (auto-starts Egregore) ─────────────────────

resource "coder_app" "terminal" {
  agent_id     = coder_agent.main.id
  slug         = "terminal"
  display_name = "Terminal"
  icon         = "/icon/terminal.svg"
  command      = "/home/egregore/.egregore-bootstrap.sh"
}
