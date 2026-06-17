import { AnimatePresence, motion } from "motion/react";
import { useEffect, useState } from "react";

import styles from "./DmConversation.module.css";

/**
 * Soft iMessage send/receive settle. framer's duration/bounce spring maps 1:1 to
 * SwiftUI's `spring(response:dampingFraction:)` that iMessage uses — here ≈
 * `.spring(response: 0.35, dampingFraction: 0.8)`.
 */
const SEND_SPRING = { type: "spring", duration: 0.35, bounce: 0.2 } as const;

/** The agent's replies, each delivered after its own "typing" beat. */
const REPLIES = ["you're early 👀", "I'll put you on before it breaks"];

/**
 * Delivery cadence, in ms from mount. Compressed to land both replies inside the
 * ~2.6s the panel is on screen, while keeping iMessage's multi-beat rhythm:
 * pause → type → reply → pause → type → reply.
 */
const PRE_TYPING_MS = 300;
const TYPING_1_MS = 650;
const GAP_MS = 250;
const TYPING_2_MS = 600;

/**
 * Conversation phase. Each step swaps what the incoming slots show; a shared
 * `layoutId` per slot morphs the typing bubble into its reply.
 */
type Phase = "idle" | "typing1" | "reply1" | "typing2" | "reply2";

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
);

const EllipsisGlyph = (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <circle cx="5" cy="12" r="1.7" />
    <circle cx="12" cy="12" r="1.7" />
    <circle cx="19" cy="12" r="1.7" />
  </svg>
);

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
);

interface DmConversationProps {
  /** Shared from the hero so motion stays gated in one place. */
  reduceMotion?: boolean | null;
  /**
   * Reports pointer enter/leave on the panel so the hero can pause its term
   * cycle while this panel is hovered. Scoped to the panel (not the wider
   * stage) so empty space beside it doesn't trigger the pause; `undefined` on
   * touch pointers.
   */
  onHoverChange?: (hovered: boolean) => void;
}

/**
 * An iMessage-style DM thread shown in the hero while the headline word is
 * "DMs". Built as real DOM (crisp + responsive) rather than a static image, and
 * animated like a real conversation: the outgoing message lands, the agent
 * "types", then its replies spring in. Under prefers-reduced-motion everything
 * renders at rest immediately. Decorative — labelled as a single image for AT.
 */
export function DmConversation({
  reduceMotion,
  onHoverChange,
}: DmConversationProps) {
  // Walk the delivery cadence; at rest jump straight to the finished thread.
  const [phase, setPhase] = useState<Phase>(reduceMotion ? "reply2" : "idle");

  useEffect(() => {
    if (reduceMotion) {
      setPhase("reply2");
      return;
    }
    setPhase("idle");
    const t1 = PRE_TYPING_MS;
    const t2 = t1 + TYPING_1_MS;
    const t3 = t2 + GAP_MS;
    const t4 = t3 + TYPING_2_MS;
    const timers = [
      setTimeout(() => setPhase("typing1"), t1),
      setTimeout(() => setPhase("reply1"), t2),
      setTimeout(() => setPhase("typing2"), t3),
      setTimeout(() => setPhase("reply2"), t4),
    ];

    return () => timers.forEach(clearTimeout);
  }, [reduceMotion]);

  // Entrance for a single bubble / stamp. `origin` anchors the scale at the
  // bubble's tail corner so it grows from where it sits, like iOS. No-op under
  // reduced motion.
  const enter = (
    delay: number,
    origin: "left" | "right" | "center" = "center",
  ) =>
    reduceMotion
      ? {}
      : {
          initial: { opacity: 0, y: 6, scale: 0.9 },
          animate: { opacity: 1, y: 0, scale: 1 },
          transition: { ...SEND_SPRING, delay },
          style: {
            transformOrigin:
              origin === "center" ? "bottom center" : `bottom ${origin}`,
          },
        };

  // Ordered incoming bubbles for the current phase. Each slot is either its
  // typing indicator or its delivered reply, sharing a `layoutId` so the dots
  // morph into the message. The last visible item carries the tail (iOS moves
  // the tail to the newest bubble).
  const slot1: "typing" | "reply" | null =
    phase === "typing1" ? "typing" : phase === "idle" ? null : "reply";
  const slot2: "typing" | "reply" | null =
    phase === "typing2" ? "typing" : phase === "reply2" ? "reply" : null;

  const incoming = [
    slot1 && { id: "dm-lead-1", kind: slot1, text: REPLIES[0] },
    slot2 && { id: "dm-lead-2", kind: slot2, text: REPLIES[1] },
  ].filter(Boolean) as { id: string; kind: "typing" | "reply"; text: string }[];

  return (
    <div
      className={styles.panel}
      role="img"
      aria-label="Example direct message with the agent zari"
      onMouseEnter={onHoverChange ? () => onHoverChange(true) : undefined}
      onMouseLeave={onHoverChange ? () => onHoverChange(false) : undefined}
    >
      <header className={styles.header} aria-hidden="true">
        <span className={styles.back}>{ChevronLeftGlyph}</span>
        <span className={styles.avatar}>
          <span className={styles.avatarCrop}>
            <img
              className={styles.avatarImg}
              src="/cards/zari.webp"
              alt=""
              draggable={false}
            />
          </span>
          <span className={styles.onlineDot} />
        </span>
        <span className={styles.identity}>
          <span className={styles.name}>zari</span>
          <span className={styles.sub}>203,402 $zari</span>
        </span>
        <span className={styles.trade}>Trade</span>
        <span className={styles.more}>{EllipsisGlyph}</span>
      </header>

      <div className={styles.thread} aria-hidden="true">
        <motion.div className={styles.dayStamp} {...enter(0)}>
          <span className={styles.dayLabel}>Today</span>
          <span className={styles.dayTime}>2:42 PM</span>
        </motion.div>

        <motion.div
          className={`${styles.bubbleRow} ${styles.outgoingRow}`}
          {...enter(0.12, "right")}
        >
          <span className={`${styles.bubble} ${styles.outgoing}`}>
            Hey zari what&apos;s next?
          </span>
        </motion.div>

        <div className={styles.incomingArea}>
          <AnimatePresence mode="popLayout" initial={false}>
            {incoming.map((item, i) => {
              const isLast = i === incoming.length - 1;
              return (
                <motion.div
                  key={item.id}
                  layoutId={item.id}
                  layout={!reduceMotion}
                  className={`${styles.bubbleRow} ${styles.incomingRow} ${
                    isLast ? "" : styles.groupedRow
                  }`}
                  {...enter(0, "left")}
                >
                  {item.kind === "typing" ? (
                    <span
                      className={`${styles.bubble} ${styles.incoming} ${styles.typing}`}
                    >
                      <span className={styles.dot} />
                      <span className={styles.dot} />
                      <span className={styles.dot} />
                    </span>
                  ) : (
                    <span
                      className={`${styles.bubble} ${styles.incoming} ${
                        isLast ? "" : styles.noTail
                      }`}
                    >
                      {item.text}
                    </span>
                  )}
                </motion.div>
              );
            })}
          </AnimatePresence>
        </div>
      </div>

      <div className={styles.inputBar} aria-hidden="true">
        <span className={styles.photo}>{PhotoGlyph}</span>
        <span className={styles.inputField}>Message…</span>
      </div>
    </div>
  );
}
