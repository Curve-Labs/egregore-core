import React, { useState, useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate, Link, useSearchParams } from 'react-router-dom'
import Dashboard from './components/Dashboard'
import OrgDetail from './components/OrgDetail'
import WaitlistAdmin from './components/WaitlistAdmin'
import { exchangeGitHubCode, getGitHubClientId } from './api'

function AuthCallback() {
  const [searchParams] = useSearchParams()
  const [error, setError] = useState(null)

  useEffect(() => {
    const code = searchParams.get('code')
    if (!code) {
      setError('No authorization code received')
      return
    }

    exchangeGitHubCode(code)
      .then(data => {
        localStorage.setItem('github_token', data.github_token)
        localStorage.setItem('github_user', JSON.stringify(data.user))
        window.location.href = '/dashboard'
      })
      .catch(err => setError(err.message))
  }, [searchParams])

  if (error) return <div style={styles.container}><p style={styles.error}>{error}</p></div>
  return <div style={styles.container}><p>Authenticating...</p></div>
}

function Login() {
  const [clientId, setClientId] = useState(null)

  useEffect(() => {
    getGitHubClientId().then(d => setClientId(d.client_id)).catch(() => {})
  }, [])

  const loginUrl = clientId
    ? `https://github.com/login/oauth/authorize?client_id=${clientId}&scope=repo,read:org`
    : null

  return (
    <div style={styles.container}>
      <h1 style={styles.title}>Egregore</h1>
      <p style={styles.subtitle}>Shared intelligence for teams</p>
      {loginUrl ? (
        <a href={loginUrl} style={styles.button}>Sign in with GitHub</a>
      ) : (
        <p>Loading...</p>
      )}
    </div>
  )
}

function Layout({ children }) {
  const user = JSON.parse(localStorage.getItem('github_user') || '{}')
  const token = localStorage.getItem('github_token')

  if (!token) return <Navigate to="/" replace />

  return (
    <div style={styles.layout}>
      <nav style={styles.nav}>
        <Link to="/dashboard" style={styles.navLink}>Egregore</Link>
        <div style={styles.navRight}>
          <span style={styles.navUser}>{user.login || 'User'}</span>
          <button
            style={styles.navButton}
            onClick={() => {
              localStorage.removeItem('github_token')
              localStorage.removeItem('github_user')
              window.location.href = '/'
            }}
          >
            Sign out
          </button>
        </div>
      </nav>
      <main style={styles.main}>{children}</main>
    </div>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Login />} />
        <Route path="/auth/callback" element={<AuthCallback />} />
        <Route path="/dashboard" element={<Layout><Dashboard /></Layout>} />
        <Route path="/org/:slug" element={<Layout><OrgDetail /></Layout>} />
        <Route path="/admin/waitlist" element={<Layout><WaitlistAdmin /></Layout>} />
      </Routes>
    </BrowserRouter>
  )
}

const styles = {
  container: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '100vh',
    fontFamily: 'system-ui, -apple-system, sans-serif',
    background: '#0a0a0a',
    color: '#e0e0e0',
  },
  title: {
    fontSize: '2.5rem',
    fontWeight: 300,
    letterSpacing: '0.1em',
    marginBottom: '0.5rem',
  },
  subtitle: {
    color: '#888',
    marginBottom: '2rem',
  },
  button: {
    display: 'inline-block',
    padding: '0.75rem 2rem',
    background: '#1a1a2e',
    color: '#e0e0e0',
    border: '1px solid #333',
    borderRadius: '6px',
    textDecoration: 'none',
    fontSize: '1rem',
    cursor: 'pointer',
  },
  error: {
    color: '#ff6b6b',
  },
  layout: {
    minHeight: '100vh',
    background: '#0a0a0a',
    color: '#e0e0e0',
    fontFamily: 'system-ui, -apple-system, sans-serif',
  },
  nav: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: '1rem 2rem',
    borderBottom: '1px solid #222',
  },
  navLink: {
    color: '#e0e0e0',
    textDecoration: 'none',
    fontSize: '1.1rem',
    fontWeight: 500,
    letterSpacing: '0.05em',
  },
  navRight: {
    display: 'flex',
    alignItems: 'center',
    gap: '1rem',
  },
  navUser: {
    color: '#888',
    fontSize: '0.9rem',
  },
  navButton: {
    background: 'none',
    border: '1px solid #333',
    color: '#888',
    padding: '0.4rem 0.8rem',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '0.85rem',
  },
  main: {
    maxWidth: '900px',
    margin: '0 auto',
    padding: '2rem',
  },
}
