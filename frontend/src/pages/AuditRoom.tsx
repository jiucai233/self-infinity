import { useEffect, useRef, useState } from 'react'
import { api } from '../api'
import type { AuditTurn, NodeType, TurnResultResponse } from '../types'

type Phase = 'loading' | 'active' | 'passed' | 'failed' | 'reflected'

// Decision note (M3 "语音讲解"): the whitepaper's end-state (§4.2) is sending
// raw audio to a multimodal model, but the backend has no audio pipeline and
// the offline MockProvider can't consume audio at all. Instead we use the
// browser-native Web Speech API to transcribe speech to text client-side and
// feed the result into the existing text `input` state / submitTurn flow
// unchanged. This ships the actual user-facing feature ("speak instead of
// type") without backend changes, and works the same regardless of which
// LLM provider is configured.
function getSpeechRecognitionCtor(): (new () => SpeechRecognitionLike) | null {
  if (typeof window === 'undefined') return null
  return window.SpeechRecognition ?? window.webkitSpeechRecognition ?? null
}

export default function AuditRoom({
  skillId,
  nodeType,
  onDone,
}: {
  skillId: number
  nodeType: NodeType
  onDone: () => void
}) {
  const isTask = nodeType === 'task'
  const roleLabel = isTask ? '任务核验官' : '费曼审计官'
  const [phase, setPhase] = useState<Phase>('loading')
  const [auditId, setAuditId] = useState<number | null>(null)
  const [turns, setTurns] = useState<AuditTurn[]>([])
  const [input, setInput] = useState('')
  const [verdict, setVerdict] = useState<TurnResultResponse | null>(null)
  const [reflection, setReflection] = useState('')
  const [principleTitle, setPrincipleTitle] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [listening, setListening] = useState(false)
  const recognitionRef = useRef<SpeechRecognitionLike | null>(null)
  const speechSupported = getSpeechRecognitionCtor() !== null

  useEffect(() => {
    return () => {
      recognitionRef.current?.stop()
    }
  }, [])

  function toggleListening() {
    if (listening) {
      recognitionRef.current?.stop()
      return
    }
    const Ctor = getSpeechRecognitionCtor()
    if (!Ctor) return
    const recognition = new Ctor()
    recognition.lang = 'zh-CN'
    recognition.continuous = true
    recognition.interimResults = false
    recognition.onresult = (event) => {
      let transcript = ''
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i]
        if (result.isFinal) transcript += result[0].transcript
      }
      if (transcript) {
        setInput((prev) => (prev ? `${prev}${transcript}` : transcript))
      }
    }
    recognition.onerror = (event) => {
      setError(
        event.error === 'not-allowed' || event.error === 'permission-denied'
          ? '麦克风权限被拒绝，无法使用语音输入'
          : `语音识别出错：${event.error}`,
      )
      setListening(false)
    }
    recognition.onend = () => {
      setListening(false)
    }
    recognitionRef.current = recognition
    setError(null)
    setListening(true)
    recognition.start()
  }

  useEffect(() => {
    api
      .startAudit(skillId)
      .then((res) => {
        setAuditId(res.session.id)
        setTurns(res.session.turns)
        setPhase('active')
      })
      .catch((e) => setError(String(e)))
  }, [skillId])

  async function submitTurn() {
    if (!auditId || !input.trim()) return
    setSubmitting(true)
    setError(null)
    const content = input.trim()
    setTurns((t) => [...t, { role: 'user', content }])
    setInput('')
    try {
      const result = await api.submitTurn(auditId, content)
      if (result.type === 'probe' && result.question) {
        setTurns((t) => [...t, { role: 'auditor', content: result.question! }])
      } else {
        setVerdict(result)
        setPhase(result.passed ? 'passed' : 'failed')
      }
    } catch (e) {
      setError(String(e))
    } finally {
      setSubmitting(false)
    }
  }

  async function submitReflection() {
    if (!auditId || !reflection.trim()) return
    setSubmitting(true)
    setError(null)
    try {
      const principle = await api.submitReflection(auditId, reflection.trim())
      setPrincipleTitle(principle.title)
      setPhase('reflected')
    } catch (e) {
      setError(String(e))
    } finally {
      setSubmitting(false)
    }
  }

  if (phase === 'loading') return <p className="dim">{roleLabel}正在入场…</p>

  return (
    <div>
      <button onClick={onDone} style={{ marginBottom: 16 }}>
        ← 返回技能树
      </button>

      <div className="panel" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        {turns.map((t, i) => (
          <div key={i}>
            <span className="dim" style={{ fontSize: 11 }}>
              {t.role === 'auditor' ? roleLabel : '你'}
            </span>
            <p style={{ marginTop: 2 }}>{t.content}</p>
          </div>
        ))}

        {phase === 'active' && (
          <div style={{ marginTop: 8 }}>
            <textarea
              rows={4}
              value={input}
              placeholder={isTask ? '说清楚具体打算怎么做…' : '讲给一个完全没听说过的人听…'}
              onChange={(e) => setInput(e.target.value)}
              disabled={submitting}
            />
            <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
              <button
                className="accent"
                onClick={submitTurn}
                disabled={submitting || !input.trim()}
              >
                {submitting ? `${roleLabel}思考中…` : isTask ? '提交说明' : '提交解释'}
              </button>
              {speechSupported && (
                <button
                  type="button"
                  onClick={toggleListening}
                  disabled={submitting}
                  style={
                    listening
                      ? { borderColor: 'var(--danger)', color: 'var(--danger)' }
                      : undefined
                  }
                  title="语音输入"
                >
                  {listening ? '● 录音中…' : '语音输入'}
                </button>
              )}
              {!speechSupported && (
                <button type="button" disabled title="此浏览器不支持语音输入">
                  语音输入
                </button>
              )}
            </div>
          </div>
        )}

        {(phase === 'passed' || phase === 'failed' || phase === 'reflected') && verdict && (
          <div
            style={{
              borderTop: '2px solid var(--border)',
              paddingTop: 12,
              marginTop: 4,
            }}
          >
            <p style={{ color: phase === 'failed' ? 'var(--danger)' : '#facc15' }}>
              {verdict.passed
                ? isTask
                  ? '✓ 任务完成'
                  : '✓ 审计通过'
                : isTask
                  ? '✗ 还没做到'
                  : '✗ 审计未通过'}{' '}
              · {verdict.score} 分
            </p>
            {verdict.passed && verdict.reward_amount != null && (
              <p style={{ fontSize: 13, marginTop: 2, color: 'var(--accent)' }}>
                +{verdict.reward_amount} 奖励
                {verdict.reward_multiplier != null && ` （×${verdict.reward_multiplier}）`}
              </p>
            )}
            <p className="dim" style={{ fontSize: 13, marginTop: 4 }}>
              {verdict.comment}
            </p>
            {verdict.gaps && verdict.gaps.length > 0 && (
              <ul style={{ fontSize: 13, marginTop: 8, paddingLeft: 18 }}>
                {verdict.gaps.map((g, i) => (
                  <li key={i}>{g}</li>
                ))}
              </ul>
            )}
            {verdict.passed && verdict.unlocked_skill_ids.length > 0 && (
              <p style={{ fontSize: 13, marginTop: 8 }}>
                解锁了 {verdict.unlocked_skill_ids.length} 个新节点
              </p>
            )}
          </div>
        )}

        {phase === 'failed' && (
          <div style={{ marginTop: 8 }}>
            <p className="dim" style={{ fontSize: 12, marginBottom: 6 }}>
              强制反思：这次为什么没讲清楚？下次会怎么做？
            </p>
            <textarea
              rows={3}
              value={reflection}
              onChange={(e) => setReflection(e.target.value)}
              disabled={submitting}
            />
            <button
              style={{ marginTop: 8 }}
              onClick={submitReflection}
              disabled={submitting || !reflection.trim()}
            >
              {submitting ? '蒸馏中…' : '提交反思，生成原则卷轴'}
            </button>
          </div>
        )}

        {phase === 'reflected' && principleTitle && (
          <div className="panel" style={{ marginTop: 8, background: 'var(--bg)' }}>
            <p style={{ fontSize: 12 }} className="dim">
              新原则卷轴
            </p>
            <p>{principleTitle}</p>
          </div>
        )}

        {phase === 'passed' && (
          <button className="accent" style={{ marginTop: 8 }} onClick={onDone}>
            返回技能树
          </button>
        )}
      </div>

      {error && (
        <p style={{ color: 'var(--danger)', marginTop: 12 }}>{error}</p>
      )}
    </div>
  )
}
