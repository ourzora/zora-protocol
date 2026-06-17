import { motion, useReducedMotion } from "motion/react";
import { useEffect, useState } from "react";

import { HEADLINE_TERMS, type HeadlineTerm } from "../data";
import styles from "./CyclingHeadline.module.css";

// Highlighter timing + easing (tuned to taste): the green punches in with a
// left→right wipe, holds solid for a beat, then its ink decays (fades out),
// telegraphing the next swap.
const WIPE_DURATION = 0.43;
const WIPE_MS = WIPE_DURATION * 1000;
const DECAY_DELAY = 0.35; // solid hold AFTER the wipe before the fade starts
const DECAY_DURATION = 1.4;
const DECAY_TARGET = 0; // ink fades fully out
// --ease-out-quint (emil): snappy release, gentle settle. Shared by wipe + decay.
const EASE_OUT_QUINT: [number, number, number, number] = [0.23, 1, 0.32, 1];

interface CyclingHeadlineProps {
  /** Active cycling term — in lockstep with the card deck via the parent. */
  term: HeadlineTerm;
}

/**
 * "Your agent's ___" where the last word cycles. The green highlight punches in
 * left → right like a highlighter pen (clip-path wipe), holds, then its ink
 * slowly fades/decays — telegraphing the next swap — until the next word punches
 * over it. No vertical motion. The line stays centred (slides as the word width
 * changes). All motion is reduced-motion-gated.
 */
export function CyclingHeadline({ term }: CyclingHeadlineProps) {
  const reduceMotion = useReducedMotion();

  // The outgoing word stays pinned beneath the incoming one (clipped to the
  // current word's width) while the highlight wipes across, then drops out.
  // `previous` is set DURING render on a term change so the old word is on
  // screen the same frame the wipe starts — no one-frame gap.
  const [snapshot, setSnapshot] = useState<{
    shown: HeadlineTerm;
    previous: HeadlineTerm | null;
  }>({ shown: term, previous: null });
  if (snapshot.shown !== term) {
    setSnapshot({
      shown: term,
      previous: reduceMotion ? null : snapshot.shown,
    });
  }

  // Drop the outgoing word once the wipe has fully passed over it.
  useEffect(() => {
    if (snapshot.previous == null) return;
    const id = setTimeout(
      () => setSnapshot((s) => ({ shown: s.shown, previous: null })),
      WIPE_MS,
    );
    return () => clearTimeout(id);
  }, [snapshot]);

  // Static, screen-reader-only phrase so the headline reads as a full sentence.
  const srPhrase = `Your agent's ${HEADLINE_TERMS.slice(0, -1).join(", ")}, and ${
    HEADLINE_TERMS[HEADLINE_TERMS.length - 1]
  }.`;

  return (
    <h1 className={styles.headline}>
      <span className={styles.srOnly}>{srPhrase}</span>

      <motion.span
        aria-hidden="true"
        className={styles.visual}
        /* Re-centre the whole line as the word width changes — position-only so
           the line slides to its new centre without scaling the text. Off under
           reduced motion. */
        layout={reduceMotion ? false : "position"}
        transition={{ duration: WIPE_DURATION, ease: EASE_OUT_QUINT }}
      >
        Your agent&rsquo;s{" "}
        <span className={styles.slot}>
          {snapshot.previous && (
            <span
              className={`${styles.word} ${styles.wordPrevious}`}
              aria-hidden="true"
            >
              <span className={styles.highlight}>{snapshot.previous}</span>
            </span>
          )}
          <motion.span
            key={term}
            className={styles.word}
            /* Highlighter wipe: reveal the green word left → right. No opacity,
               no translate. clip-path inset animates the right edge in. */
            initial={reduceMotion ? false : { clipPath: "inset(0 100% 0 0)" }}
            animate={reduceMotion ? {} : { clipPath: "inset(0 0% 0 0)" }}
            transition={{ duration: WIPE_DURATION, ease: EASE_OUT_QUINT }}
          >
            <span className={styles.highlight}>
              {/* Marker ink behind the text. Punches in solid with the wipe,
                  holds, then its opacity decays so the fading green telegraphs
                  the next swap. Held solid under reduced motion. */}
              {reduceMotion ? (
                <span className={styles.highlightInk} aria-hidden="true" />
              ) : (
                <motion.span
                  className={styles.highlightInk}
                  aria-hidden="true"
                  initial={{ opacity: 1 }}
                  animate={{ opacity: DECAY_TARGET }}
                  transition={{
                    delay: WIPE_DURATION + DECAY_DELAY,
                    duration: DECAY_DURATION,
                    ease: EASE_OUT_QUINT,
                  }}
                />
              )}
              {term}
            </span>
          </motion.span>
        </span>
      </motion.span>

      {/* Polite live region announces the changing word without re-reading the
          whole sentence. */}
      <span aria-live="polite" className={styles.srOnly}>
        {term}
      </span>
    </h1>
  );
}
