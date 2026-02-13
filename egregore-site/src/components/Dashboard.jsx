import React, { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { getUserOrgs, getUserProfile } from '../api'

export default function Dashboard() {
  const [profile, setProfile] = useState(null)
  const [orgs, setOrgs] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const token = localStorage.getItem('github_token')

  useEffect(() => {
    if (!token) return

    Promise.all([
      getUserProfile(token).catch(() => null),
      getUserOrgs(token).catch(() => ({ orgs: [] })),
    ])
      .then(([profileData, orgsData]) => {
        setProfile(profileData)
        setOrgs(orgsData?.orgs || [])
      })
      .catch(err => setError(err.message))
      .finally(() => setLoading(false))
  }, [token])

  if (loading) return <p style={styles.muted}>Loading...</p>
  if (error) return <p style={styles.error}>{error}</p>

  return (
    <div>
      <h1 style={styles.heading}>Dashboard</h1>

      {profile && (
        <div style={styles.profileCard}>
          <div style={styles.profileInfo}>
            <strong>{profile.name || profile.github_username}</strong>
            <span style={styles.muted}>@{profile.github_username}</span>
            {profile.telegram_username && (
              <span style={styles.muted}>Telegram: @{profile.telegram_username}</span>
            )}
          </div>
        </div>
      )}

      <h2 style={styles.subheading}>Your Organizations</h2>

      {orgs.length === 0 ? (
        <p style={styles.muted}>No organizations yet.</p>
      ) : (
        <div style={styles.orgList}>
          {orgs.map(org => (
            <Link
              key={org.slug}
              to={`/org/${org.slug}`}
              style={styles.orgCard}
            >
              <div style={styles.orgName}>{org.name}</div>
              <div style={styles.orgMeta}>
                <span style={styles.badge}>{org.role}</span>
                {org.has_telegram && <span style={styles.badge}>Telegram</span>}
              </div>
              <div style={styles.orgSlug}>{org.github_org}</div>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}

const styles = {
  heading: {
    fontSize: '1.8rem',
    fontWeight: 400,
    marginBottom: '1.5rem',
    letterSpacing: '0.02em',
  },
  subheading: {
    fontSize: '1.2rem',
    fontWeight: 400,
    marginTop: '2rem',
    marginBottom: '1rem',
    color: '#aaa',
  },
  profileCard: {
    background: '#111',
    border: '1px solid #222',
    borderRadius: '8px',
    padding: '1.25rem',
    marginBottom: '1rem',
  },
  profileInfo: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.3rem',
  },
  orgList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.75rem',
  },
  orgCard: {
    display: 'block',
    background: '#111',
    border: '1px solid #222',
    borderRadius: '8px',
    padding: '1.25rem',
    textDecoration: 'none',
    color: '#e0e0e0',
    transition: 'border-color 0.15s',
  },
  orgName: {
    fontSize: '1.1rem',
    fontWeight: 500,
    marginBottom: '0.4rem',
  },
  orgMeta: {
    display: 'flex',
    gap: '0.5rem',
    marginBottom: '0.3rem',
  },
  orgSlug: {
    color: '#666',
    fontSize: '0.85rem',
  },
  badge: {
    display: 'inline-block',
    padding: '0.15rem 0.5rem',
    background: '#1a1a2e',
    border: '1px solid #333',
    borderRadius: '4px',
    fontSize: '0.75rem',
    color: '#aaa',
  },
  muted: {
    color: '#666',
  },
  error: {
    color: '#ff6b6b',
  },
}
