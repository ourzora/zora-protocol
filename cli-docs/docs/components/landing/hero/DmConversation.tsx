import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useState } from 'react'

import { DM_THREAD } from '../data'
import styles from './DmConversation.module.css'

/**
 * Clean, no-bounce settle for messages entering — a soft fade + small rise
 * (easeOutQuint). Avoids the scale pop/bounce that read as clunky; smooth per the
 * /emil-design-engineering enter guidance (ease-out, transform + opacity only).
 */
const EASE_OUT: [number, number, number, number] = [0.22, 1, 0.36, 1]

/** Persona + script live in `data.ts` (single source for all landing copy). */
const REPLIES = DM_THREAD.replies

/**
 * Delivery cadence, in ms from mount. The reply lands by ~1.2s, then holds for
 * the rest of the hero dwell.
 */
const PRE_TYPING_MS = 300
const TYPING_MS = 850

/**
 * Conversation phase. The incoming slot first shows typing, then morphs into
 * the delivered reply via a shared `layoutId`.
 */
type Phase = 'idle' | 'typing' | 'reply'

/** Bare inline glyphs — same convention as `PlatformLogo`. */
const ChevronLeftGlyph = (
  <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <path
      d="M15 18l-6-6 6-6"
      stroke="currentColor"
      strokeWidth="2.2"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
)

const EllipsisGlyph = (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <circle cx="5" cy="12" r="1.7" />
    <circle cx="12" cy="12" r="1.7" />
    <circle cx="19" cy="12" r="1.7" />
  </svg>
)

const PhotoGlyph = (
  <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <rect
      x="3"
      y="3"
      width="18"
      height="18"
      rx="4"
      stroke="currentColor"
      strokeWidth="1.7"
    />
    <circle cx="8.5" cy="8.5" r="1.7" fill="currentColor" />
    <path
      d="M21 15.5l-4.5-4.5L5 22"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
)

interface DmConversationProps {
  /** Shared from the hero so motion stays gated in one place. */
  reduceMotion?: boolean | null
  /**
   * Reports pointer enter/leave on the panel so the hero can pause its term
   * cycle while this panel is hovered. Scoped to the panel (not the wider
   * stage) so empty space beside it doesn't trigger the pause; `undefined` on
   * touch pointers.
   */
  onHoverChange?: (hovered: boolean) => void
}

/**
 * An iMessage-style DM thread shown in the hero while the headline word is
 * "DMs". Built as real DOM (crisp + responsive) rather than a static image, and
 * animated like a real conversation: the outgoing message lands, the agent
 * "types", then its reply springs in. Under prefers-reduced-motion everything
 * renders at rest immediately. Decorative — labelled as a single image for AT.
 */
export function DmConversation({ reduceMotion, onHoverChange }: DmConversationProps) {
  // Walk the delivery cadence; at rest jump straight to the finished thread.
  const [phase, setPhase] = useState<Phase>(reduceMotion ? 'reply' : 'idle')

  useEffect(() => {
    if (reduceMotion) {
      setPhase('reply')
      return
    }
    setPhase('idle')
    const t1 = PRE_TYPING_MS
    const t2 = t1 + TYPING_MS
    const timers = [
      setTimeout(() => setPhase('typing'), t1),
      setTimeout(() => setPhase('reply'), t2),
    ]

    return () => timers.forEach(clearTimeout)
  }, [reduceMotion])

  // Entrance for a single bubble / stamp — a soft fade + small rise, no scale,
  // no bounce. No-op under reduced motion.
  const enter = (delay: number) =>
    reduceMotion
      ? {}
      : {
          initial: { opacity: 0, y: 8 },
          animate: { opacity: 1, y: 0 },
          transition: { duration: 0.34, ease: EASE_OUT, delay },
        }

  // Distinct ids for typing vs reply so AnimatePresence cross-fades them in place
  // (typing fades out, reply fades + rises in) rather than the typing pill
  // inflating into the reply via a shared layout morph — which read as clunky.
  const incoming =
    phase === 'idle'
      ? []
      : phase === 'typing'
        ? [{ id: 'dm-typing', kind: 'typing' as const, text: '' }]
        : REPLIES.map((text, i) => ({
            id: `dm-reply-${i}`,
            kind: 'reply' as const,
            text,
          }))

  return (
    <div
      className={styles.panel}
      role="img"
      aria-label={`Example direct message with the agent ${DM_THREAD.name}`}
      onMouseEnter={onHoverChange ? () => onHoverChange(true) : undefined}
      onMouseLeave={onHoverChange ? () => onHoverChange(false) : undefined}
    >
      <header className={styles.header} aria-hidden="true">
        <span className={styles.back}>{ChevronLeftGlyph}</span>
        <span className={styles.avatar}>
          <span className={styles.avatarCrop}>
            <img
              className={styles.avatarImg}
              src={DM_THREAD.avatar}
              alt=""
              draggable={false}
            />
          </span>
          <motion.span
            className={styles.onlineDot}
            {...(reduceMotion
              ? {}
              : {
                  initial: { scale: 0, opacity: 0 },
                  animate: { scale: 1, opacity: 1 },
                  // Arrive LAST — a beat after the panel has settled in.
                  transition: { delay: 0.5, type: 'spring', stiffness: 500, damping: 26 },
                })}
          />
        </span>
        <span className={styles.identity}>
          <span className={styles.name}>{DM_THREAD.name}</span>
          <span className={styles.sub}>{DM_THREAD.token}</span>
        </span>
        <span className={styles.trade}>Trade</span>
        <span className={styles.more}>{EllipsisGlyph}</span>
      </header>

      <div className={styles.thread} aria-hidden="true">
        <motion.div
          className={`${styles.bubbleRow} ${styles.outgoingRow}`}
          {...enter(0.05)}
        >
          <span className={`${styles.bubble} ${styles.outgoing}`}>
            {DM_THREAD.outgoing}
          </span>
        </motion.div>

        <div className={styles.incomingArea}>
          <AnimatePresence mode="popLayout" initial={false}>
            {incoming.map((item, i) => {
              const isLast = i === incoming.length - 1
              return (
                <motion.div
                  key={item.id}
                  className={`${styles.bubbleRow} ${styles.incomingRow} ${
                    isLast ? '' : styles.groupedRow
                  }`}
                  {...enter(0)}
                  exit={
                    reduceMotion
                      ? undefined
                      : { opacity: 0, transition: { duration: 0.16 } }
                  }
                >
                  {item.kind === 'typing' ? (
                    <span
                      className={`${styles.bubble} ${styles.incoming} ${styles.typing}`}
                    >
                      <span className={styles.dot} />
                      <span className={styles.dot} />
                      <span className={styles.dot} />
                    </span>
                  ) : (
                    <span className={`${styles.bubble} ${styles.incoming}`}>
                      {item.text}
                    </span>
                  )}
                </motion.div>
              )
            })}
          </AnimatePresence>
        </div>
      </div>

      <div className={styles.inputBar} aria-hidden="true">
        <span className={styles.photo}>{PhotoGlyph}</span>
        <span className={styles.inputField}>Message...</span>
      </div>
    </div>
  )
}
