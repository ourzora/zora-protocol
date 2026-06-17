import { motion, useReducedMotion } from "motion/react";

import { DEV_TOOLS } from "./data";
import { Icon, type IconName } from "./Icon";
import { Reveal, RevealGroup, RevealItem } from "./Reveal";
import { useCopyToClipboard } from "./lib/useCopyToClipboard";
import styles from "./DeveloperTools.module.css";

/** Pick the column glyph by tool label, defaulting to the code icon. */
function iconFor(label: string): Extract<IconName, "code" | "sparkle"> {
  return label.toLowerCase() === "skill" ? "sparkle" : "code";
}

interface CopyableSnippetProps {
  snippet: string;
  /** Used for the copy button's accessible label, e.g. "CLI". */
  label: string;
}

/* Copy-glyph geometry lifted from the library's IconSquareBehindSquare1
   (24-viewBox): the back square is an OPEN path — the segment that would pass
   behind the front square is simply omitted, so the two shapes never read as
   incorrectly overlapping strokes. On copy the back path slides onto the front
   square and fades while the front square grows to a centered 17.5×17.5 with
   its corner radius animating to half its size — which IS the square→circle
   morph, no path interpolation needed. */
const BACK_D = "M15.25 8.75V2.75H2.75V15.25H8.75";
const FRONT_REST = { x: 8.75, y: 8.75, width: 12.5, height: 12.5, rx: 0 };
const FRONT_CIRCLE = { x: 3.25, y: 3.25, width: 17.5, height: 17.5, rx: 8.75 };
const BACK_REST = { x: 0, y: 0, opacity: 1 };
const BACK_MERGED = { x: 6, y: 6, opacity: 0 };

/** SwiftUI-style springs, same family as the hero DM panel. */
const MORPH_SPRING = { type: "spring", duration: 0.3, bounce: 0.2 } as const;
const DRAW_SPRING = {
  type: "spring",
  duration: 0.25,
  bounce: 0.15,
  delay: 0.12,
} as const;

/**
 * The copy→check morph from the reference interaction: the copy icon's two
 * squares merge as the front square rounds into a circle, then a check draws
 * itself inside via stroke pathLength. Reset reverses the whole thing. Under
 * reduced motion every value snaps (duration 0) — no draw, no morph, never a
 * stuck-hidden state. Everything inherits currentColor so the whole glyph
 * (check included) tracks the affordance color.
 */
function CopyMorphIcon({ copied }: { copied: boolean }) {
  const reduceMotion = useReducedMotion();
  const morph = reduceMotion ? { duration: 0 } : MORPH_SPRING;
  const draw = reduceMotion ? { duration: 0 } : DRAW_SPRING;

  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="square"
      aria-hidden="true"
    >
      <motion.path
        d={BACK_D}
        initial={false}
        animate={copied ? BACK_MERGED : BACK_REST}
        transition={morph}
      />
      <motion.rect
        initial={false}
        animate={copied ? FRONT_CIRCLE : FRONT_REST}
        transition={morph}
      />
      <motion.path
        d="M8 12.4 L10.9 15.3 L16.2 8.9"
        initial={false}
        animate={{ pathLength: copied ? 1 : 0, opacity: copied ? 1 : 0 }}
        transition={copied ? draw : morph}
      />
    </svg>
  );
}

/**
 * Boxed monospace command that copies to the clipboard when clicked. The whole
 * box is the button — the design shows no "Copy" label, just the command with a
 * small copy affordance on the right that morphs into a circled check on
 * success (see `CopyMorphIcon`).
 */
function CopyableSnippet({ snippet, label }: CopyableSnippetProps) {
  const { copied, copy } = useCopyToClipboard();

  return (
    <button
      type="button"
      className={styles.snippet}
      onClick={() => copy(snippet)}
      aria-label={copied ? `${label} command copied` : `Copy ${label} command`}
    >
      <code className={styles.snippetText}>{snippet}</code>
      <span
        className={styles.copyAffordance}
        data-copied={copied || undefined}
        aria-hidden="true"
      >
        <CopyMorphIcon copied={copied} />
      </span>
    </button>
  );
}

/**
 * "Developer Tools" section.
 *
 * A centered display heading over two columns (CLI + Skill). Each column is a
 * centered vertical stack — icon, title, description, and a copyable command
 * box — with no outer card border. Columns stack to one on narrow screens.
 */
export function DeveloperTools() {
  return (
    <section className={styles.section} aria-labelledby="devtools-heading">
      <Reveal>
        <h2 id="devtools-heading" className={`agentsDisplay ${styles.heading}`}>
          Developer Tools
        </h2>
      </Reveal>

      <RevealGroup className={styles.grid}>
        {DEV_TOOLS.map((tool) => {
          const icon = iconFor(tool.label);
          return (
            <RevealItem key={tool.label} className={styles.cell}>
              <article className={styles.column}>
                <div className={styles.text}>
                  <div className={styles.titleRow}>
                    <Icon name={icon} className={styles.icon} size={32} />
                    <h3 className={`agentsTitle ${styles.title}`}>
                      {tool.label}
                    </h3>
                  </div>
                  <p className={`agentsBody ${styles.body}`}>{tool.body}</p>
                </div>
                <CopyableSnippet snippet={tool.snippet} label={tool.label} />
                <a href={tool.href} className={styles.docsLink}>
                  {tool.linkLabel} ↗
                </a>
              </article>
            </RevealItem>
          );
        })}
      </RevealGroup>
    </section>
  );
}
