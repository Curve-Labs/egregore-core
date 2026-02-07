import { useState, useCallback, useRef, useEffect } from 'react'
import { useOracleStore } from '../hooks/useOracleState'
import { COLORS } from '../lib/constants'

interface InputOverlayProps {
  onSubmit?: (question: string) => void
}

export function InputOverlay({ onSubmit }: InputOverlayProps) {
  const [inputValue, setInputValue] = useState('')
  const [isExpanded, setIsExpanded] = useState(false)
  const inputRef = useRef<HTMLTextAreaElement>(null)

  const mode = useOracleStore((s) => s.mode)
  const oracleState = useOracleStore((s) => s.oracleState)
  const setQuestion = useOracleStore((s) => s.setQuestion)
  const setOracleState = useOracleStore((s) => s.setOracleState)
  const answer = useOracleStore((s) => s.answer)
  const revealProgress = useOracleStore((s) => s.revealProgress)

  const isOracleMode = mode === 'oracle'
  const isThinking = oracleState === 'thinking'
  const isRevealing = oracleState === 'revealing'
  const isComplete = oracleState === 'complete'

  const handleSubmit = useCallback(() => {
    if (!inputValue.trim() || isThinking) return

    setQuestion(inputValue)
    setOracleState('thinking')
    onSubmit?.(inputValue)
    setInputValue('')
    setIsExpanded(false)
  }, [inputValue, isThinking, setQuestion, setOracleState, onSubmit])

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault()
        handleSubmit()
      }
      if (e.key === 'Escape') {
        setIsExpanded(false)
        inputRef.current?.blur()
      }
    },
    [handleSubmit]
  )

  const handleFocus = useCallback(() => {
    setIsExpanded(true)
  }, [])

  // Auto-focus when entering oracle mode
  useEffect(() => {
    if (isOracleMode && oracleState === 'idle') {
      inputRef.current?.focus()
    }
  }, [isOracleMode, oracleState])

  // Get revealed portion of answer
  const revealedAnswer = answer.slice(0, Math.floor(answer.length * revealProgress))

  if (!isOracleMode) return null

  return (
    <div
      style={{
        position: 'absolute',
        bottom: '10%',
        left: '50%',
        transform: 'translateX(-50%)',
        width: '90%',
        maxWidth: '600px',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: '1rem',
        pointerEvents: 'auto',
        zIndex: 10,
      }}
    >
      {/* Answer display */}
      {(isRevealing || isComplete) && revealedAnswer && (
        <div
          style={{
            width: '100%',
            padding: '1.5rem',
            background: 'rgba(10, 10, 15, 0.9)',
            border: `1px solid ${COLORS.dim}`,
            borderRadius: '8px',
            color: COLORS.highlight,
            fontFamily: 'monospace',
            fontSize: '1rem',
            lineHeight: 1.6,
            whiteSpace: 'pre-wrap',
            maxHeight: '40vh',
            overflowY: 'auto',
          }}
        >
          {revealedAnswer}
          {isRevealing && (
            <span
              style={{
                opacity: 0.5,
                animation: 'blink 1s infinite',
              }}
            >
              _
            </span>
          )}
        </div>
      )}

      {/* Thinking indicator */}
      {isThinking && (
        <div
          style={{
            color: COLORS.accent,
            fontFamily: 'monospace',
            fontSize: '0.9rem',
            display: 'flex',
            alignItems: 'center',
            gap: '0.5rem',
          }}
        >
          <span style={{ animation: 'pulse 1.5s infinite' }}>
            The oracle contemplates...
          </span>
        </div>
      )}

      {/* Input area */}
      {oracleState === 'idle' && (
        <div
          style={{
            width: '100%',
            display: 'flex',
            flexDirection: 'column',
            gap: '0.5rem',
          }}
        >
          <textarea
            ref={inputRef}
            value={inputValue}
            onChange={(e) => setInputValue(e.target.value)}
            onKeyDown={handleKeyDown}
            onFocus={handleFocus}
            placeholder="Ask the oracle..."
            style={{
              width: '100%',
              padding: '1rem',
              background: 'rgba(10, 10, 15, 0.8)',
              border: `1px solid ${isExpanded ? COLORS.accent : COLORS.dim}`,
              borderRadius: '8px',
              color: COLORS.highlight,
              fontFamily: 'monospace',
              fontSize: '1rem',
              resize: 'none',
              outline: 'none',
              transition: 'border-color 0.3s, height 0.3s',
              height: isExpanded ? '100px' : '50px',
            }}
          />

          {isExpanded && (
            <button
              onClick={handleSubmit}
              disabled={!inputValue.trim()}
              style={{
                alignSelf: 'flex-end',
                padding: '0.5rem 1.5rem',
                background: inputValue.trim() ? COLORS.accent : COLORS.dim,
                border: 'none',
                borderRadius: '4px',
                color: COLORS.highlight,
                fontFamily: 'monospace',
                fontSize: '0.9rem',
                cursor: inputValue.trim() ? 'pointer' : 'not-allowed',
                transition: 'background 0.3s',
              }}
            >
              Ask
            </button>
          )}
        </div>
      )}

      {/* Reset button after complete */}
      {isComplete && (
        <button
          onClick={() => {
            setOracleState('idle')
            useOracleStore.getState().setAnswer('')
            useOracleStore.getState().setRevealProgress(0)
          }}
          style={{
            padding: '0.5rem 1.5rem',
            background: 'rgba(10, 10, 15, 0.8)',
            border: `1px solid ${COLORS.dim}`,
            borderRadius: '4px',
            color: COLORS.mid,
            fontFamily: 'monospace',
            fontSize: '0.9rem',
            cursor: 'pointer',
            transition: 'border-color 0.3s, color 0.3s',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.borderColor = COLORS.accent
            e.currentTarget.style.color = COLORS.highlight
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.borderColor = COLORS.dim
            e.currentTarget.style.color = COLORS.mid
          }}
        >
          Ask another question
        </button>
      )}

      <style>{`
        @keyframes blink {
          0%, 50% { opacity: 1; }
          51%, 100% { opacity: 0; }
        }
        @keyframes pulse {
          0%, 100% { opacity: 0.5; }
          50% { opacity: 1; }
        }
      `}</style>
    </div>
  )
}
