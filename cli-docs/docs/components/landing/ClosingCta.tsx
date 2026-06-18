import { motion, useAnimationControls, useReducedMotion } from "motion/react";

import { CLOSING, SETUP_FALLBACK_HREF, SETUP_PROMPT } from "./data";
import { RevealGroup, RevealItem } from "./Reveal";
import { useCopyToClipboard } from "./lib/useCopyToClipboard";
import { useHoverCapable } from "./lib/useHoverCapable";
import styles from "./ClosingCta.module.css";

/**
 * Closing call-to-action section for the agents.zora.com landing page
 * (Figma node 2093:148).
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
  const secondaryHref = CLOSING.secondaryCta.href;
  const secondaryIsExternal = /^https?:\/\//.test(secondaryHref);
  // Primary CTA copies the setup prompt — same action as the hero's top CTA.
  const { copied, copy } = useCopyToClipboard();

  // Same fallback as the hero CTA: if the clipboard isn't available, send the
  // user to the skill docs page so the setup instructions are still reachable.
  const copyOrFallback = () => {
    void copy(SETUP_PROMPT).then((ok) => {
      if (!ok && typeof window !== "undefined") {
        window.location.href = SETUP_FALLBACK_HREF;
      }
    });
  };

  // Fire a one-shot "reaction" wiggle on hover-enter (cartoon head-tilt, per
  // /emil-design-engineering). Triggered imperatively rather than via whileHover
  // so the keyframe sequence always plays through to rest (rotate: 0) — a quick
  // pointer flick can't strand the head at a tilt. The leading `null` keyframe
  // means a re-trigger animates from the CURRENT angle, so rapid re-hovers are
  // smoothly interruptible (no snap-to-0). On-screen movement → ease-in-out.
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
            <motion.button
              type="button"
              onClick={copyOrFallback}
              data-copied={copied}
              className={`${styles.cta} ${styles.ctaPrimary}`}
              aria-label={
                copied
                  ? "Setup prompt copied to clipboard"
                  : `Copy setup prompt: ${SETUP_PROMPT}`
              }
              {...ctaMotion}
            >
              {/* Width reserved by the wider label so the pill never resizes. */}
              <span className={styles.labelSlot}>
                <span className={styles.labelSizer} aria-hidden="true">
                  {CLOSING.primaryCta.label}
                </span>
                <span className={styles.label}>
                  {copied ? "Copied" : CLOSING.primaryCta.label}
                </span>
              </span>
            </motion.button>
            <motion.a
              href={secondaryHref}
              {...(secondaryIsExternal
                ? { target: "_blank", rel: "noopener noreferrer" }
                : {})}
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
