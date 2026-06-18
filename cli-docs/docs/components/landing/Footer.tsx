import { motion, useMotionValue, useReducedMotion, useTransform } from 'motion/react'
import { useEffect, useRef, useState } from 'react'

import { FOOTER } from './data'
import styles from './Footer.module.css'

/** External links open in a new tab; in-site docs links navigate in place. */
function linkTarget(href: string) {
  return /^https?:\/\//.test(href)
    ? { target: '_blank', rel: 'noopener noreferrer' }
    : {}
}

/**
 * Standalone Zora wordmark (no zorb icon) — the official logotype
 * ("Zora Wordmark White", viewBox 0 0 3960 1441). Inline SVG so it inherits
 * `currentColor` (white here) and scales without distortion.
 */
const ZoraWordmark = (
  <svg
    className={styles.logo}
    viewBox="0 0 3960 1441"
    fill="currentColor"
    role="img"
    aria-label="Zora"
  >
    <path d="M1918.03 425.382C1835.94 380.079 1741.03 357 1633.28 357C1525.54 357 1428.06 379.224 1345.97 424.527C1263.88 468.976 1201.45 532.229 1157.84 613.433C1114.23 694.636 1092 789.516 1092 898.073C1092 1006.63 1113.38 1107.49 1157.84 1189.55C1201.45 1270.75 1263.88 1333.15 1345.11 1375.89C1426.35 1418.63 1522.97 1440 1634.99 1440C1747.01 1440 1835.94 1417.78 1917.18 1374.18C1998.41 1329.73 2061.69 1267.34 2105.3 1185.28C2149.77 1103.22 2172 1007.48 2172 898.927C2172 790.371 2149.77 697.201 2106.16 615.997C2062.55 534.793 2000.12 471.54 1918.03 425.382ZM1630.72 1192.12C1473.38 1192.12 1425.49 1036.55 1425.49 900.637C1425.49 764.728 1473.38 607.449 1630.72 607.449C1788.06 607.449 1837.65 767.292 1837.65 900.637C1837.65 1033.98 1789.77 1192.12 1630.72 1192.12Z" />
    <path d="M2735.32 387.414C2686.65 407.4 2647.55 439.551 2615.4 482.999C2592.81 513.413 2586 522 2565 561V363.083L2229 363.082V1440.59H2565V1075.5C2565 942 2584.12 881.853 2606.71 833.191C2629.3 784.529 2663.19 748.902 2706.64 726.309C2750.96 704.585 2805.7 693.288 2870.01 693.288C2888.25 693.288 2900.42 693.288 2922.14 696.764V357H2900.42C2838.72 357 2783.11 367.428 2735.32 387.414Z" />
    <path d="M1080 0V336L422.03 1104H1080V1440H0V1104L658.83 336H0V0H1080Z" />
    <path d="M3960 1224.09V714.066C3960 633.313 3942.14 567.009 3905.56 514.307C3868.98 462.455 3815.39 424.203 3744.79 399.552C3674.19 374.901 3589.12 363 3489.6 363C3412.19 363 3343.29 369.8 3281.19 383.401C3219.1 397.002 3166.36 417.403 3122.98 446.304C3078.74 474.355 3045.57 512.607 3023.45 561.059C3003.89 602.711 2994.53 649.463 2993.68 707.266H3333.93C3339.04 669.864 3349.25 646.063 3367.11 627.362C3390.93 601.861 3428.35 589.111 3478.54 589.111C3511.72 589.111 3537.24 592.511 3555.95 599.311C3574.66 606.111 3589.12 617.162 3600.18 631.612C3608.69 641.813 3613.79 654.564 3616.34 668.164C3620.6 706.416 3633.36 759.118 3502.36 778.669L3355.2 805.021C3270.14 819.471 3199.53 838.172 3142.54 859.423C3086.4 880.674 3040.47 912.976 3004.74 954.628C2969.86 996.279 2952 1053.23 2952 1124.64C2952 1191.79 2968.16 1249.59 2999.64 1296.34C3031.96 1343.95 3074.49 1379.65 3128.93 1403.45C3183.37 1428.1 3245.47 1440 3314.37 1440C3378.17 1440 3435.16 1429.8 3484.5 1408.55C3534.68 1387.3 3574.66 1360.1 3606.14 1325.24C3612.94 1317.59 3617.19 1309.09 3623.15 1300.59V1440H3960V1223.24V1224.09ZM3567.01 1171.39C3529.58 1202.84 3481.09 1218.14 3421.55 1218.14C3384.12 1218.14 3355.2 1209.64 3333.08 1192.64C3310.97 1175.64 3299.91 1150.14 3299.91 1116.99C3299.91 1083.83 3310.12 1058.33 3332.23 1041.33C3353.5 1024.33 3384.97 1011.58 3427.5 1002.23L3623.15 959.728V1023.48C3623.15 1090.63 3604.44 1139.09 3567.01 1171.39Z" />
  </svg>
)

/**
 * Full-width footer bar for the agents.zora.com landing page (Figma node
 * 2093:183).
 *
 * Black background with link columns (docs + Zora ecosystem — everything
 * reachable from the docs site this page replaces) above the wordmark/domain
 * row. Stacks to a left-aligned column on narrow screens.
 *
 * The reveal is a scroll-linked parallax: as the footer scrolls into view its
 * contents drift up and fade in, scrubbed to scroll position. The wordmark
 * carries extra depth so the two layers move at different rates — that
 * differential is what reads as parallax rather than a one-shot fade.
 *
 * The footer renders FULLY VISIBLE by default (plain elements). The parallax is
 * layered on only after mount, and only when motion is allowed. This keeps the
 * footer visible without JS and under `prefers-reduced-motion`, and means the
 * hidden→reveal state is never the default that could get stuck.
 */
export function Footer() {
  const reduceMotion = useReducedMotion()
  const ref = useRef<HTMLElement>(null)
  const [animate, setAnimate] = useState(false)

  // Reveal progress (0 → 1) as the footer enters the viewport. Driven manually
  // rather than via framer's `useScroll`: this page scrolls on <body> (the
  // global `overflow-x: hidden` makes body the scroll container, not the
  // document), so a window-based useScroll never sees the scroll. A
  // getBoundingClientRect read on a capture-phase scroll listener works no
  // matter which element actually scrolls (scroll events don't bubble, but they
  // still pass through the capture phase at the window).
  const progress = useMotionValue(0)

  useEffect(() => {
    if (reduceMotion) return
    const el = ref.current
    if (!el) return
    setAnimate(true)

    let frame = 0
    const measure = () => {
      frame = 0
      const rect = el.getBoundingClientRect()
      const vh = window.innerHeight || document.documentElement.clientHeight
      // 0 when the footer's top reaches the viewport bottom → 1 when its bottom
      // does (matches framer's ['start end', 'end end'] offset).
      const p = (vh - rect.top) / (rect.height || 1)
      progress.set(Math.min(1, Math.max(0, p)))
    }
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(measure)
    }

    measure()
    window.addEventListener('scroll', onScroll, { passive: true, capture: true })
    window.addEventListener('resize', onScroll, { passive: true })
    return () => {
      if (frame) cancelAnimationFrame(frame)
      window.removeEventListener('scroll', onScroll, { capture: true })
      window.removeEventListener('resize', onScroll)
    }
  }, [reduceMotion, progress])

  // The content group rises + fades in as the footer enters view. Positive y
  // starts it below its resting place so it slides up into position. The footer
  // is short and its content sits near the top, so it comes on screen only in
  // the back half of the entrance — fade over [0.3, 0.9] so it reads as fading
  // in as it appears rather than arriving pre-lit. The wordmark + domain share
  // this one motion (no separate logo depth) so they stay locked together and
  // the domain never drifts off the logo's baseline.
  const innerY = useTransform(progress, [0, 1], [80, 0])
  const innerOpacity = useTransform(progress, [0.3, 0.9], [0, 1])

  const linkColumns = (
    <nav className={styles.columns} aria-label="Footer">
      {FOOTER.columns.map((links) => (
        <ul key={links[0].label} className={styles.column}>
          {links.map((link) => (
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
      ))}
    </nav>
  )

  return (
    <footer ref={ref} className={styles.footer}>
      {animate ? (
        <motion.div
          className={styles.content}
          style={{ y: innerY, opacity: innerOpacity }}
        >
          {linkColumns}
          <div className={styles.inner}>
            {ZoraWordmark}
            <span className={styles.domain}>{FOOTER.domain}</span>
          </div>
        </motion.div>
      ) : (
        <div className={styles.content}>
          {linkColumns}
          <div className={styles.inner}>
            {ZoraWordmark}
            <span className={styles.domain}>{FOOTER.domain}</span>
          </div>
        </div>
      )}
    </footer>
  )
}
