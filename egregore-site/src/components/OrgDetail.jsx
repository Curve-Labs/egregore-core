import React, { useState, useEffect } from 'react'
import { useParams, Link } from 'react-router-dom'
import { getUserOrgs, getOrgMembers, getTelegramStatus, sendInvite } from '../api'

export default function OrgDetail() {
  const { slug } = useParams()
  const [org, setOrg] = useState(null)
  const [members, setMembers] = useState([])
  const [telegram, setTelegram] = useState(null)
  const [loading, setLoading] = useState(true)
  const [inviteUsername, setInviteUsername] = useState('')
  const [inviteResult, setInviteResult] = useState(null)
  const [inviting, setInviting] = useState(false)

  const token = localStorage.getItem('github_token')

  useEffect(() => {
    if (!token) return

    const loadData = async () => {
      try {
        // Get org info from user's orgs list
        const orgsData = await getUserOrgs(token)
        const found = (orgsData?.orgs || []).find(o => o.slug === slug)
        setOrg(found || { slug, name: slug })

        // Try to get members (needs API key — may fail for non-admin)
        try {
          // Members endpoint requires API key, not GitHub token
          // For now, this will only work if we have the API key
          // In production, add a GitHub-token-authed members endpoint
        } catch {}

        // Get telegram status (public endpoint)
        try {
          const tg = await getTelegramStatus(slug)
          setTelegram(tg)
        } catch {}
      } catch (err) {
        console.error('Failed to load org:', err)
      } finally {
        setLoading(false)
      }
    }

    loadData()
  }, [token, slug])

  const handleInvite = async (e) => {
    e.preventDefault()
    if (!inviteUsername.trim()) return

    setInviting(true)
    setInviteResult(null)

    try {
      const result = await sendInvite(token, {
        github_org: org?.github_org || slug,
        github_username: inviteUsername.trim(),
      })
      setInviteResult({ success: true, url: result.invite_url })
      setInviteUsername('')
    } catch (err) {
      setInviteResult({ success: false, error: err.message })
    } finally {
      setInviting(false)
    }
  }

  if (loading) return <p style={styles.muted}>Loading...</p>

  return (
    <div>
      <Link to="/dashboard" style={styles.backLink}>Back to dashboard</Link>

      <h1 style={styles.heading}>{org?.name || slug}</h1>
      <p style={styles.muted}>{org?.github_org || slug}</p>

      {/* Telegram status */}
      <section style={styles.section}>
        <h2 style={styles.subheading}>Telegram</h2>
        {telegram?.connected ? (
          <div style={styles.card}>
            <span style={styles.statusDot} />
            Connected: {telegram.group_title || 'Group'}
            {telegram.group_username && (
              <span style={styles.muted}> @{telegram.group_username}</span>
            )}
          </div>
        ) : (
          <div style={styles.card}>
            <span style={{ ...styles.statusDot, background: '#666' }} />
            Not connected
          </div>
        )}
      </section>

      {/* Members */}
      <section style={styles.section}>
        <h2 style={styles.subheading}>Team</h2>
        {members.length === 0 ? (
          <p style={styles.muted}>Member list requires API key authentication.</p>
        ) : (
          <div style={styles.memberList}>
            {members.map((m, i) => (
              <div key={i} style={styles.memberRow}>
                <span>{m.github_username || 'Unknown'}</span>
                <span style={styles.badge}>{m.role}</span>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Invite */}
      <section style={styles.section}>
        <h2 style={styles.subheading}>Invite</h2>
        <form onSubmit={handleInvite} style={styles.inviteForm}>
          <input
            type="text"
            placeholder="GitHub username"
            value={inviteUsername}
            onChange={e => setInviteUsername(e.target.value)}
            style={styles.input}
          />
          <button type="submit" disabled={inviting} style={styles.button}>
            {inviting ? 'Sending...' : 'Send invite'}
          </button>
        </form>
        {inviteResult && (
          <div style={inviteResult.success ? styles.success : styles.error}>
            {inviteResult.success
              ? `Invite sent! Link: ${inviteResult.url}`
              : `Error: ${inviteResult.error}`
            }
          </div>
        )}
      </section>
    </div>
  )
}

const styles = {
  heading: {
    fontSize: '1.8rem',
    fontWeight: 400,
    marginBottom: '0.25rem',
    letterSpacing: '0.02em',
  },
  subheading: {
    fontSize: '1.1rem',
    fontWeight: 400,
    marginBottom: '0.75rem',
    color: '#aaa',
  },
  section: {
    marginTop: '2rem',
  },
  card: {
    background: '#111',
    border: '1px solid #222',
    borderRadius: '8px',
    padding: '1rem',
    display: 'flex',
    alignItems: 'center',
    gap: '0.5rem',
  },
  statusDot: {
    width: '8px',
    height: '8px',
    borderRadius: '50%',
    background: '#4ade80',
    display: 'inline-block',
  },
  memberList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.5rem',
  },
  memberRow: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    background: '#111',
    border: '1px solid #222',
    borderRadius: '6px',
    padding: '0.75rem 1rem',
  },
  badge: {
    padding: '0.15rem 0.5rem',
    background: '#1a1a2e',
    border: '1px solid #333',
    borderRadius: '4px',
    fontSize: '0.75rem',
    color: '#aaa',
  },
  inviteForm: {
    display: 'flex',
    gap: '0.5rem',
  },
  input: {
    flex: 1,
    padding: '0.6rem 0.8rem',
    background: '#111',
    border: '1px solid #333',
    borderRadius: '6px',
    color: '#e0e0e0',
    fontSize: '0.95rem',
    outline: 'none',
  },
  button: {
    padding: '0.6rem 1.2rem',
    background: '#1a1a2e',
    border: '1px solid #333',
    borderRadius: '6px',
    color: '#e0e0e0',
    cursor: 'pointer',
    fontSize: '0.95rem',
  },
  backLink: {
    color: '#666',
    textDecoration: 'none',
    fontSize: '0.9rem',
    display: 'inline-block',
    marginBottom: '1rem',
  },
  muted: {
    color: '#666',
  },
  success: {
    color: '#4ade80',
    marginTop: '0.75rem',
    fontSize: '0.9rem',
  },
  error: {
    color: '#ff6b6b',
    marginTop: '0.75rem',
    fontSize: '0.9rem',
  },
}
