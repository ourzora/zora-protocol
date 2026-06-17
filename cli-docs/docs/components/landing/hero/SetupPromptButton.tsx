import { motion, useReducedMotion } from "motion/react";

import { SETUP_PROMPT } from "../data";
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
 *
 * If copying isn't possible (insecure origin with no Clipboard API, or a
 * permissions rejection) we don't fake a "Copied" state — instead we send the
 * user to the skill page, which has the same prompt written out to copy by hand.
 */
export function SetupPromptButton() {
  const reduceMotion = useReducedMotion();
  const hoverable = useHoverCapable();
  const { copied, copy } = useCopyToClipboard();

  const handleClick = async () => {
    const didCopy = await copy(SETUP_PROMPT);
    if (!didCopy && typeof window !== "undefined") {
      window.location.href = "/skill";
    }
  };

  return (
    <motion.button
      type="button"
      className={styles.pill}
      onClick={handleClick}
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
          <Icon name="copy" size={22} />
        </span>
        <span className={styles.glyph} data-show={copied}>
          <Icon name="check" size={22} />
        </span>
      </span>
    </motion.button>
  );
}
