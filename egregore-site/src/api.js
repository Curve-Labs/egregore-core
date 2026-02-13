/**
 * Egregore API client for the dashboard.
 */

const API_URL = import.meta.env.VITE_API_URL || ''

async function request(path, options = {}) {
  const url = `${API_URL}${path}`
  const headers = { 'Content-Type': 'application/json', ...options.headers }
  const resp = await fetch(url, { ...options, headers })
  if (!resp.ok) {
    const body = await resp.json().catch(() => ({}))
    throw new Error(body.detail || `Request failed: ${resp.status}`)
  }
  return resp.json()
}

function authHeaders(token) {
  return { Authorization: `Bearer ${token}` }
}

// --- Auth ---

export async function getGitHubClientId() {
  return request('/api/auth/github/client-id')
}

export async function exchangeGitHubCode(code) {
  return request('/api/auth/github/callback', {
    method: 'POST',
    body: JSON.stringify({ code }),
  })
}

// --- User ---

export async function getUserProfile(githubToken) {
  return request('/api/user/profile', {
    headers: authHeaders(githubToken),
  })
}

export async function getUserOrgs(githubToken) {
  return request('/api/user/orgs', {
    headers: authHeaders(githubToken),
  })
}

export async function updateUserProfile(githubToken, telegramUsername) {
  return request('/api/user/profile', {
    method: 'POST',
    headers: authHeaders(githubToken),
    body: JSON.stringify({ telegram_username: telegramUsername }),
  })
}

// --- Org ---

export async function getOrgMembers(apiKey, slug) {
  return request(`/api/org/${slug}/members`, {
    headers: authHeaders(apiKey),
  })
}

export async function getOrgStatus(apiKey) {
  return request('/api/org/status', {
    headers: authHeaders(apiKey),
  })
}

export async function getTelegramStatus(slug) {
  return request(`/api/org/telegram/status/${slug}`)
}

// --- Setup ---

export async function getSetupOrgs(githubToken) {
  return request('/api/org/setup/orgs', {
    headers: authHeaders(githubToken),
  })
}

export async function setupOrg(githubToken, data) {
  return request('/api/org/setup', {
    method: 'POST',
    headers: authHeaders(githubToken),
    body: JSON.stringify(data),
  })
}

export async function joinOrg(githubToken, data) {
  return request('/api/org/join', {
    method: 'POST',
    headers: authHeaders(githubToken),
    body: JSON.stringify(data),
  })
}

// --- Invite ---

export async function getInviteInfo(token) {
  return request(`/api/org/invite/${token}`)
}

export async function acceptInvite(githubToken, inviteToken) {
  return request(`/api/org/invite/${inviteToken}/accept`, {
    method: 'POST',
    headers: authHeaders(githubToken),
  })
}

export async function sendInvite(apiKey, data) {
  return request('/api/org/invite', {
    method: 'POST',
    headers: authHeaders(apiKey),
    body: JSON.stringify(data),
  })
}

// --- Waitlist ---

export async function addToWaitlist(data) {
  return request('/api/admin/waitlist', {
    method: 'POST',
    body: JSON.stringify(data),
  })
}

export async function getWaitlist(apiKey, status = 'pending') {
  return request(`/api/admin/waitlist?status=${status}`, {
    headers: authHeaders(apiKey),
  })
}

export async function approveWaitlist(apiKey, waitlistId) {
  return request('/api/admin/waitlist/approve', {
    method: 'POST',
    headers: authHeaders(apiKey),
    body: JSON.stringify({ waitlist_id: waitlistId }),
  })
}
