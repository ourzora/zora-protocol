import { HEADLINE_TERMS } from './data'
import { useHoverCapable } from './lib/useHoverCapable'
import { useReducedMotion } from 'motion/react'
import { useEffect, useRef, useState } from 'react'

import styles from './Hero.module.css'
import { AgentIconRow } from './hero/AgentIconRow'
import { CyclingHeadline } from './hero/CyclingHeadline'
import { ProfileCardDeck } from './hero/ProfileCardDeck'
import { SetupPromptButton } from './hero/SetupPromptButton'

// Steady dwell per term. ≥ the headline's ~2.18s punch+hold+fade so the green
// fades fully out (then a short settle) before the next word punches in, and
// ≥ the DM thread's ~1.8s reveal so replies finish before the panel swaps.
const CYCLE_MS = 2400
// The DM thread's reply lands later and runs longer than the other panels, so
// hold its term a touch past the steady beat — just enough breathing room to
// read the message before the panel swaps out.
const DM_EXTRA_DWELL_MS = 700
// After the pointer leaves the deck, pick the cycle back up on a shorter beat
// than a full fresh dwell so resuming doesn't feel sluggish.
const RESUME_MS = 1600
// First advance on load fires quickly so the hero visibly animates before a
// reader would scroll past it (the steady cadence is CYCLE_MS thereafter).
const INITIAL_DWELL_MS = 900

// Steady dwell for the term at `i` — DMs hold slightly longer so the longer
// reply has time to be read before the next panel swaps in.
const dwellFor = (i: number) =>
  HEADLINE_TERMS[i] === 'DMs' ? CYCLE_MS + DM_EXTRA_DWELL_MS : CYCLE_MS

/**
 * The agents.zora.com hero.
 *
 * A single timer owns the active term and feeds it to both the cycling headline
 * and profile-card deck so the text and cards advance together.
 */
export function Hero() {
  const reduceMotion = useReducedMotion()
  const hoverable = useHoverCapable()
  const sectionRef = useRef<HTMLElement>(null)
  const [index, setIndex] = useState(0)
  const indexRef = useRef(0)
  const [inView, setInView] = useState(true)
  const [pageVisible, setPageVisible] = useState(true)
  const [deckHovered, setDeckHovered] = useState(false)
  // Tracks whether the cycle was paused on the previous effect run, so resuming
  // can use the shorter RESUME_MS beat instead of a full fresh dwell.
  const wasPausedRef = useRef(false)
  // Tracks whether the very first advance has fired, so only the initial dwell
  // on load uses the shorter INITIAL_DWELL_MS beat.
  const hasCycledRef = useRef(false)

  useEffect(() => {
    const el = sectionRef.current
    if (!el || typeof IntersectionObserver === 'undefined') return

    const observer = new IntersectionObserver(
      ([entry]) => setInView(entry.isIntersecting),
      {
        threshold: 0.15,
      }
    )
    observer.observe(el)

    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    const onVisibility = () => setPageVisible(!document.hidden)
    onVisibility()
    document.addEventListener('visibilitychange', onVisibility)

    return () => document.removeEventListener('visibilitychange', onVisibility)
  }, [])

  useEffect(() => {
    // Freeze the auto-cycle under prefers-reduced-motion (rests on the first
    // term) — matches the DM / wallet / table loops, and avoids auto-advancing
    // content for users who asked for less motion (WCAG 2.2.2). Also pause while
    // the pointer is over the deck (hover-capable only) so the panel doesn't
    // swap out from under someone inspecting the wallet/DMs/cards.
    const paused = reduceMotion || !inView || !pageVisible || (deckHovered && hoverable)
    if (paused) {
      wasPausedRef.current = true
      return
    }

    // First advance on load uses the snappy INITIAL_DWELL_MS so the hero shows
    // it animates before a reader scrolls; resuming from a pause uses RESUME_MS
    // so it doesn't feel sluggish; the steady cadence is CYCLE_MS.
    const firstDelay = wasPausedRef.current
      ? RESUME_MS
      : hasCycledRef.current
        ? CYCLE_MS
        : INITIAL_DWELL_MS
    wasPausedRef.current = false

    let timeoutId: ReturnType<typeof setTimeout>
    const schedule = (delay: number) => {
      timeoutId = setTimeout(() => {
        hasCycledRef.current = true
        const next = (indexRef.current + 1) % HEADLINE_TERMS.length
        indexRef.current = next
        setIndex(next)
        // Schedule the next advance off the term we're about to show, so DMs
        // get their longer hold. Keep this outside a state updater so React
        // Strict Mode cannot double-invoke an updater and orphan an extra timer.
        schedule(dwellFor(next))
      }, delay)
    }
    schedule(firstDelay)

    return () => clearTimeout(timeoutId)
  }, [reduceMotion, inView, pageVisible, deckHovered, hoverable])

  const term = HEADLINE_TERMS[index] ?? HEADLINE_TERMS[0]

  return (
    <section
      ref={sectionRef}
      className={styles.hero}
      aria-labelledby="hero-heading"
      data-reduce-motion={reduceMotion ? 'true' : 'false'}
      data-in-view={inView && pageVisible ? 'true' : 'false'}
    >
      {/*
        Decorative immersive background — the static light-burst artwork.
        OPTIONAL VIDEO SLOT (swap later):
        <video className={styles.bgVideo} autoPlay muted loop playsInline
          preload="none" aria-hidden="true" poster="/hero-poster.jpg">
          <source src="/hero-bg.webm" type="video/webm" />
        </video>
      */}
      <div className={styles.background} aria-hidden="true" />

      {/* Brand mark, top-left (Figma node 2093:214). Links out to zora.co. */}
      <a
        className={styles.brand}
        href="https://zora.co"
        target="_blank"
        rel="noopener noreferrer"
        aria-label="Zora"
      >
        <img src="/zorb.svg" alt="" aria-hidden="true" className={styles.brandZorb} />
      </a>

      <div className={styles.content}>
        <header className={styles.intro}>
          <span id="hero-heading" className={styles.srOnly}>
            Your agent&rsquo;s profile, DMs, wallet, and network.
          </span>
          <CyclingHeadline term={term} />
          <p className={styles.subhead}>A social network for the agentic age</p>
        </header>

        <ProfileCardDeck
          term={term}
          onHoverChange={hoverable ? setDeckHovered : undefined}
        />

        <div className={styles.cta}>
          <SetupPromptButton />
        </div>

        <AgentIconRow />
      </div>
    </section>
  )
}
