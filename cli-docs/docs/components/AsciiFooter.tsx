"use client";
import { useRef, useCallback, useMemo, useEffect } from "react";

/* ----------------------------------------------------------------
 * Letter bitmaps — "Zora" (cap Z + lowercase ora)
 * # = filled glyph, space = transparent
 * Z is 16 wide × 13 tall (cap height)
 * o, r, a are 12/11/12 wide × 8 content rows, padded to 13
 * ---------------------------------------------------------------- */

const Z = [
  "################",
  "################",
  "################",
  "        ########",
  "       ######## ",
  "     ########   ",
  "    ########    ",
  "   ########     ",
  " ########       ",
  "########        ",
  "################",
  "################",
  "################",
];

const o = [
  "            ",
  "            ",
  "            ",
  "            ",
  "            ",
  "   ######   ",
  " ########## ",
  "####    ####",
  "####    ####",
  "####    ####",
  "####    ####",
  " ########## ",
  "   ######   ",
];

const r = [
  "           ",
  "           ",
  "           ",
  "           ",
  "           ",
  "####  #####",
  "###########",
  "###########",
  "#####      ",
  "####       ",
  "####       ",
  "####       ",
  "####       ",
];

const a = [
  "            ",
  "            ",
  "            ",
  "            ",
  "            ",
  "  ########  ",
  " ########## ",
  "####    ####",
  "        ####",
  "  ##########",
  "####    ####",
  "#####  #####",
  " ########## ",
];

const GAP = "  ";
const ROWS = 13;

const GLYPHS = ["\u2191", "\u25A0", "Z", "O", "R", "A", " "];

const TEMPLATE = Array.from({ length: ROWS }, (_, i) =>
  (Z[i] + GAP + o[i] + GAP + r[i] + GAP + a[i]).split(""),
);

function buildGrid(tick: number) {
  let seed = tick * 7 + 13;
  const rng = () =>
    (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
  const pick = () => GLYPHS[Math.floor(rng() * GLYPHS.length)];

  return TEMPLATE.map((row) => {
    const line = row.map((c) => (c === "#" ? pick() + pick() : "  ")).join("");
    return line + "\n" + line;
  }).join("\n");
}

export function AsciiFooter() {
  const wrapRef = useRef<HTMLElement>(null);
  const preRef = useRef<HTMLPreElement>(null);
  const grid = useMemo(() => buildGrid(0), []);
  const delays = useMemo(() => {
    let seed = 42;
    const rng = () =>
      (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
    return [...grid].map((ch) =>
      /\S/.test(ch) ? Math.round(rng() * 500) : -1,
    );
  }, [grid]);

  useEffect(() => {
    const el = wrapRef.current;
    const pre = preRef.current;
    if (!el || !pre) return;

    // Set initial blank content (all non-whitespace replaced with spaces)
    pre.textContent = grid.replace(/\S/g, " ");

    let rafId: number;
    const obs = new IntersectionObserver(
      ([e]) => {
        if (!e.isIntersecting) return;
        obs.unobserve(pre);
        el.classList.add("visible");

        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
          pre.textContent = grid;
          /* animation complete */
          return;
        }

        const gridChars = [...grid];
        const start = performance.now();
        const animate = () => {
          const elapsed = performance.now() - start;
          let text = "";
          let pending = false;
          for (let i = 0; i < gridChars.length; i++) {
            const d = delays[i];
            if (d < 0 || elapsed >= d) {
              text += gridChars[i];
            } else {
              text += " ";
              pending = true;
            }
          }
          pre.textContent = text;
          if (pending) {
            rafId = requestAnimationFrame(animate);
          } else {
            /* animation complete */
          }
        };
        rafId = requestAnimationFrame(animate);
      },
      { threshold: 0.3 },
    );
    obs.observe(pre);
    return () => {
      obs.disconnect();
      cancelAnimationFrame(rafId);
    };
  }, [grid, delays]);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    const el = preRef.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    el.style.setProperty("--mx", `${e.clientX - rect.left}px`);
    el.style.setProperty("--my", `${e.clientY - rect.top}px`);
  }, []);

  const handleMouseLeave = useCallback(() => {
    const el = preRef.current;
    if (!el) return;
    el.style.setProperty("--mx", "-9999px");
    el.style.setProperty("--my", "-9999px");
  }, []);

  return (
    <footer ref={wrapRef} className="ascii-footer-wrap">
      <div className="ascii-footer-top">
        <nav className="ascii-footer-links">
          <h4 className="ascii-footer-heading">Follow us</h4>
          <a
            href="https://github.com/ourzora"
            target="_blank"
            rel="noopener noreferrer"
          >
            GitHub
          </a>
          <a
            href="https://www.instagram.com/our.zora"
            target="_blank"
            rel="noopener noreferrer"
          >
            Instagram
          </a>
          <a
            href="https://x.com/zora"
            target="_blank"
            rel="noopener noreferrer"
          >
            Twitter
          </a>
          <a href="https://zora.co" target="_blank" rel="noopener noreferrer">
            Zora.co
          </a>
        </nav>
        <pre
          ref={preRef}
          className="ascii-footer"
          onMouseMove={handleMouseMove}
          onMouseLeave={handleMouseLeave}
          suppressHydrationWarning
        />
        {/* Content managed via textContent in the useEffect RAF loop.
            Rendering as JSX children would conflict with direct DOM mutations. */}
      </div>
    </footer>
  );
}
