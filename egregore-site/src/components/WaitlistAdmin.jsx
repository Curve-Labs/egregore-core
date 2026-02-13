import React, { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { getWaitlist, approveWaitlist } from '../api'

export default function WaitlistAdmin() {
  const [entries, setEntries] = useState([])
  const [filter, setFilter] = useState('pending')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  // Waitlist admin requires an API key (stored separately from GitHub token)
  const apiKey = localStorage.getItem('api_key')

  const loadEntries = async () => {
    if (!apiKey) {
      setError('API key required. Set it in localStorage as "api_key".')
      setLoading(false)
      return
    }

    setLoading(true)
    try {
      const data = await getWaitlist(apiKey, filter)
      setEntries(data.entries || [])
      setError(null)
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadEntries()
  }, [filter, apiKey])

  const handleApprove = async (id) => {
    if (!apiKey) return
    try {
      await approveWaitlist(apiKey, id)
      loadEntries()
    } catch (err) {
      setError(err.message)
    }
  }

  return (
    <div>
      <Link to="/dashboard" style={styles.backLink}>Back to dashboard</Link>

      <h1 style={styles.heading}>Waitlist</h1>

      <div style={styles.filters}>
        {['pending', 'approved', 'rejected'].map(s => (
          <button
            key={s}
            onClick={() => setFilter(s)}
            style={{
              ...styles.filterButton,
              ...(filter === s ? styles.filterActive : {}),
            }}
          >
            {s}
          </button>
        ))}
      </div>

      {error && <p style={styles.error}>{error}</p>}
      {loading && <p style={styles.muted}>Loading...</p>}

      {!loading && entries.length === 0 && (
        <p style={styles.muted}>No {filter} entries.</p>
      )}

      <div style={styles.list}>
        {entries.map(entry => (
          <div key={entry.id} style={styles.card}>
            <div style={styles.cardMain}>
              <div>
                {entry.email && <div>{entry.email}</div>}
                {entry.github_username && (
                  <div style={styles.muted}>@{entry.github_username}</div>
                )}
                {entry.source && (
                  <div style={styles.source}>via {entry.source}</div>
                )}
              </div>
              <div style={styles.cardRight}>
                <span style={styles.date}>
                  {new Date(entry.created_at).toLocaleDateString()}
                </span>
                {filter === 'pending' && (
                  <button
                    onClick={() => handleApprove(entry.id)}
                    style={styles.approveButton}
                  >
                    Approve
                  </button>
                )}
                {filter === 'approved' && entry.approved_at && (
                  <span style={styles.approved}>
                    Approved {new Date(entry.approved_at).toLocaleDateString()}
                  </span>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>
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
  filters: {
    display: 'flex',
    gap: '0.5rem',
    marginBottom: '1.5rem',
  },
  filterButton: {
    padding: '0.4rem 0.8rem',
    background: '#111',
    border: '1px solid #333',
    borderRadius: '4px',
    color: '#888',
    cursor: 'pointer',
    fontSize: '0.85rem',
  },
  filterActive: {
    borderColor: '#666',
    color: '#e0e0e0',
  },
  list: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.5rem',
  },
  card: {
    background: '#111',
    border: '1px solid #222',
    borderRadius: '8px',
    padding: '1rem',
  },
  cardMain: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  cardRight: {
    display: 'flex',
    alignItems: 'center',
    gap: '0.75rem',
  },
  date: {
    color: '#666',
    fontSize: '0.85rem',
  },
  source: {
    color: '#555',
    fontSize: '0.8rem',
    marginTop: '0.2rem',
  },
  approveButton: {
    padding: '0.35rem 0.8rem',
    background: '#1a2e1a',
    border: '1px solid #2a4a2a',
    borderRadius: '4px',
    color: '#4ade80',
    cursor: 'pointer',
    fontSize: '0.85rem',
  },
  approved: {
    color: '#4ade80',
    fontSize: '0.8rem',
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
  error: {
    color: '#ff6b6b',
    marginBottom: '1rem',
  },
}
