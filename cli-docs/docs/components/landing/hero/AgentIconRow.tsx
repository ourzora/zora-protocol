import { motion, useReducedMotion } from "motion/react";

import { AGENT_TOOLS } from "../data";
import { useHoverCapable } from "../lib/useHoverCapable";
import styles from "./AgentIconRow.module.css";
import { PlatformLogo } from "./PlatformLogo";

/** Snappy spring with a hint of life — Emil's "alive" micro-interaction. */
const HOVER_SPRING = { type: "spring", stiffness: 400, damping: 22 } as const;

/**
 * "Works with every agent" caption plus a row of bare monochrome platform marks
 * (no chip boxes, evenly spaced on one centerline). Each mark grows a touch on
 * hover with a spring — gated to hover-capable pointers (so a touch tap never
 * triggers it) and skipped under reduced motion.
 */
export function AgentIconRow() {
  const reduceMotion = useReducedMotion();
  const hoverable = useHoverCapable();

  return (
    <div className={styles.row}>
      <p className={styles.caption}>Works with every agent</p>
      <ul className={styles.chips}>
        {AGENT_TOOLS.map((tool) => (
          <motion.li
            key={tool.name}
            className={styles.chip}
            title={tool.name}
            whileHover={
              hoverable && !reduceMotion ? { scale: 1.08 } : undefined
            }
            transition={HOVER_SPRING}
          >
            <PlatformLogo id={tool.logoId} size={36} className={styles.logo} />
            <span className={styles.srOnly}>{tool.name}</span>
          </motion.li>
        ))}
      </ul>
    </div>
  );
}
