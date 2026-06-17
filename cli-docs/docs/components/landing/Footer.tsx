import {
  motion,
  useMotionValue,
  useReducedMotion,
  useTransform,
} from "motion/react";
import { useEffect, useRef, useState } from "react";

import { FOOTER } from "./data";
import styles from "./Footer.module.css";

/** External links open in a new tab; in-site docs links navigate in place. */
function linkTarget(href: string) {
  return /^https?:\/\//.test(href)
    ? { target: "_blank", rel: "noopener noreferrer" }
    : {};
}

/**
 * Full-width footer bar.
 *
 * Black background with link columns (docs + Zora ecosystem) above the
 * wordmark/domain row. Stacks to a left-aligned column on narrow screens.
 *
 * The reveal is a scroll-linked parallax: as the footer scrolls into view its
 * contents drift up and fade in, scrubbed to scroll position.
 *
 * The footer renders FULLY VISIBLE by default (plain elements). The parallax is
 * layered on only after mount, and only when motion is allowed. This keeps the
 * footer visible without JS and under `prefers-reduced-motion`, and means the
 * hidden→reveal state is never the default that could get stuck.
 */
export function Footer() {
  const reduceMotion = useReducedMotion();
  const ref = useRef<HTMLElement>(null);
  const [animate, setAnimate] = useState(false);

  // Reveal progress (0 → 1) as the footer enters the viewport. Driven manually
  // via a capture-phase scroll listener so it works no matter which element
  // actually scrolls (the page may scroll on <body> rather than the document).
  const progress = useMotionValue(0);

  useEffect(() => {
    if (reduceMotion) return;
    const el = ref.current;
    if (!el) return;
    setAnimate(true);

    let frame = 0;
    const measure = () => {
      frame = 0;
      const rect = el.getBoundingClientRect();
      const vh = window.innerHeight || document.documentElement.clientHeight;
      // 0 when the footer's top reaches the viewport bottom → 1 when its bottom
      // does (matches framer's ['start end', 'end end'] offset).
      const p = (vh - rect.top) / (rect.height || 1);
      progress.set(Math.min(1, Math.max(0, p)));
    };
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(measure);
    };

    measure();
    window.addEventListener("scroll", onScroll, {
      passive: true,
      capture: true,
    });
    window.addEventListener("resize", onScroll, { passive: true });
    return () => {
      if (frame) cancelAnimationFrame(frame);
      window.removeEventListener("scroll", onScroll, { capture: true });
      window.removeEventListener("resize", onScroll);
    };
  }, [reduceMotion, progress]);

  // The content group rises + fades in as the footer enters view.
  const innerY = useTransform(progress, [0, 1], [80, 0]);
  const innerOpacity = useTransform(progress, [0.3, 0.9], [0, 1]);

  const linkColumns = (
    <nav className={styles.columns} aria-label="Footer">
      {FOOTER.columns.map((column) => (
        <div key={column.title} className={styles.column}>
          <span className={styles.columnTitle}>{column.title}</span>
          <ul className={styles.columnLinks}>
            {column.links.map((link) => (
              <li key={link.label}>
                <a
                  href={link.href}
                  className={styles.link}
                  {...linkTarget(link.href)}
                >
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </nav>
  );

  const wordmarkRow = (
    <div className={styles.inner}>
      <img src="/zora-logo.webp" alt="Zora" className={styles.logo} />
      <span className={styles.domain}>{FOOTER.domain}</span>
    </div>
  );

  return (
    <footer ref={ref} className={styles.footer}>
      {animate ? (
        <motion.div
          className={styles.content}
          style={{ y: innerY, opacity: innerOpacity }}
        >
          {linkColumns}
          {wordmarkRow}
        </motion.div>
      ) : (
        <div className={styles.content}>
          {linkColumns}
          {wordmarkRow}
        </div>
      )}
    </footer>
  );
}
