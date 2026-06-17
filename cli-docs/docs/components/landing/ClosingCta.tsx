import { motion, useAnimationControls, useReducedMotion } from "motion/react";

import { CLOSING } from "./data";
import { RevealGroup, RevealItem } from "./Reveal";
import { useHoverCapable } from "./lib/useHoverCapable";
import styles from "./ClosingCta.module.css";

/**
 * Closing call-to-action section.
 *
 * White, centered. A decorative "AGENT" lockup — the gray glyph mark followed
 * by a bordered pill reading AGENT — sits up top, then the display headline, a
 * muted subtext line, and two CTAs (solid primary + outline secondary) that
 * stack to a column on narrow screens.
 */
export function ClosingCta() {
  const reduceMotion = useReducedMotion();
  const hoverable = useHoverCapable();
  const glyphWiggle = useAnimationControls();

  // Fire a one-shot "reaction" wiggle on hover-enter (cartoon head-tilt).
  // Triggered imperatively rather than via whileHover so the keyframe sequence
  // always plays through to rest (rotate: 0) — a quick pointer flick can't
  // strand the head at a tilt. The leading `null` keyframe means a re-trigger
  // animates from the CURRENT angle, so rapid re-hovers are smoothly
  // interruptible (no snap-to-0). On-screen movement → ease-in-out.
  const playGlyphWiggle = () => {
    if (reduceMotion || !hoverable) return;
    void glyphWiggle.start(
      { rotate: [null, -8, 6, -3, 0] },
      { duration: 0.55, ease: "easeInOut" },
    );
  };

  // Press/lift micro-interaction on the CTAs — transforms only. Hover-grow is
  // gated to hover-capable pointers so a touch tap doesn't trigger it; whileTap
  // gives touch its own press feedback. Skipped entirely under reduced motion
  // (plain anchors render instead).
  const ctaMotion = reduceMotion
    ? {}
    : {
        ...(hoverable ? { whileHover: { scale: 1.03 } } : {}),
        whileTap: { scale: 0.97 },
        transition: { duration: 0.18, ease: "easeOut" as const },
      };

  return (
    <section className={styles.section}>
      <RevealGroup className={styles.inner}>
        {/* Decorative AGENT lockup: glyph mark + bordered "AGENT" pill. */}
        <RevealItem>
          <span className={styles.lockup}>
            <motion.img
              src="/agent-glyph.svg"
              alt=""
              aria-hidden="true"
              className={styles.lockupGlyph}
              style={{ transformOrigin: "bottom center" }}
              animate={glyphWiggle}
              onHoverStart={playGlyphWiggle}
            />
            <span className={styles.lockupPill} aria-hidden="true">
              AGENT
            </span>
          </span>
        </RevealItem>

        <RevealItem>
          <h2 className={`agentsDisplay ${styles.headline}`}>
            {CLOSING.headline}
          </h2>
        </RevealItem>

        <RevealItem>
          <p className={styles.subtext}>{CLOSING.body}</p>
        </RevealItem>

        <RevealItem>
          <div className={styles.actions}>
            <motion.a
              href={CLOSING.primaryCta.href}
              className={`${styles.cta} ${styles.ctaPrimary}`}
              {...ctaMotion}
            >
              {CLOSING.primaryCta.label}
            </motion.a>
            <motion.a
              href={CLOSING.secondaryCta.href}
              className={`${styles.cta} ${styles.ctaSecondary}`}
              {...ctaMotion}
            >
              {CLOSING.secondaryCta.label}
            </motion.a>
          </div>
        </RevealItem>
      </RevealGroup>
    </section>
  );
}
