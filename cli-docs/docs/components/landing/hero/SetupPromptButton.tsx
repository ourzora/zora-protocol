import { motion, useReducedMotion } from "motion/react";

import { SETUP_FALLBACK_HREF, SETUP_PROMPT } from "../data";
import { Icon } from "../Icon";
import { useCopyToClipboard } from "../lib/useCopyToClipboard";
import { useHoverCapable } from "../lib/useHoverCapable";
import styles from "./SetupPromptButton.module.css";

/** Springy but snappy — grows on hover, presses down on tap, settles fast. */
const PRESS_SPRING = { type: "spring", stiffness: 500, damping: 30 } as const;

/**
 * Dark pill that copies the setup prompt to the clipboard and flips to a
 * "Copied" confirmation for ~1.8s. Label width is reserved so the pill does not
 * resize when the text changes (zero layout shift). Hover-grow is gated to
 * hover-capable pointers; tap-press feedback works on touch.
 */
export function SetupPromptButton() {
  const reduceMotion = useReducedMotion();
  const hoverable = useHoverCapable();
  const { copied, copy } = useCopyToClipboard();

  // Copy the prompt; if the clipboard isn't available (insecure origin, no
  // Clipboard API, or a denied permission) fall back to the skill docs page so
  // the user still reaches the setup instructions instead of getting nothing.
  const copyOrFallback = () => {
    void copy(SETUP_PROMPT).then((ok) => {
      if (!ok && typeof window !== "undefined") {
        window.location.href = SETUP_FALLBACK_HREF;
      }
    });
  };

  return (
    <motion.button
      type="button"
      className={styles.pill}
      onClick={copyOrFallback}
      data-copied={copied}
      whileHover={hoverable && !reduceMotion ? { scale: 1.04 } : undefined}
      whileTap={reduceMotion ? undefined : { scale: 0.96 }}
      transition={PRESS_SPRING}
      aria-label={
        copied
          ? "Setup prompt copied to clipboard"
          : `Copy setup prompt: ${SETUP_PROMPT}`
      }
    >
      {/* Width is reserved by the wider label so the pill never resizes. */}
      <span className={styles.labelSlot}>
        <span className={styles.labelSizer} aria-hidden="true">
          Copy setup prompt
        </span>
        <span className={styles.label}>
          {copied ? "Copied" : "Copy setup prompt"}
        </span>
      </span>

      <span className={styles.icon} aria-hidden="true">
        {/* Cross-fade the glyph; both stacked so width never changes. */}
        <span className={styles.glyph} data-show={!copied}>
          <Icon name="copy" size={24} />
        </span>
        <span className={styles.glyph} data-show={copied}>
          <Icon name="check" size={24} />
        </span>
      </span>
    </motion.button>
  );
}
