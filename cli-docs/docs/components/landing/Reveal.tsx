import { motion, useReducedMotion, type Variants } from 'motion/react'
import type { ReactNode } from 'react'

/**
 * Subtle, craft-led scroll-reveal primitives.
 *
 * Elements fade + rise a touch as they enter the viewport, ONCE (no replay on
 * scroll up/down). Motion is opacity + transform only and tuned per
 * /emil-design-engineering (ease-out, ~0.6s). Under `prefers-reduced-motion`
 * every reveal renders as a plain, fully-visible element — which also guards
 * against content ever being stuck hidden.
 *
 * - `Reveal`      — a single element that reveals on enter.
 * - `RevealGroup` — a container whose `RevealItem` children reveal in a stagger.
 */

const EASE_OUT_QUART = [0.165, 0.84, 0.44, 1] as const
const DURATION = 0.6
const OFFSET = '16px'

const itemVariants: Variants = {
  hidden: { opacity: 0, transform: `translateY(${OFFSET})` },
  visible: {
    opacity: 1,
    transform: 'translateY(0px)',
    transition: { duration: DURATION, ease: EASE_OUT_QUART },
  },
}

const groupVariants: Variants = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.08, delayChildren: 0.04 } },
}

interface RevealProps {
  children: ReactNode
  className?: string
  /** Extra delay before this element reveals, in seconds. */
  delay?: number
  /** Fraction of the element that must be in view before revealing (0–1). */
  amount?: number
}

export function Reveal({ children, className, delay = 0, amount = 0.25 }: RevealProps) {
  const reduceMotion = useReducedMotion()

  if (reduceMotion) {
    return <div className={className}>{children}</div>
  }

  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, transform: `translateY(${OFFSET})` }}
      whileInView={{ opacity: 1, transform: 'translateY(0px)' }}
      viewport={{ once: true, amount }}
      transition={{ duration: DURATION, ease: EASE_OUT_QUART, delay }}
    >
      {children}
    </motion.div>
  )
}

interface RevealGroupProps {
  children: ReactNode
  className?: string
  amount?: number
}

/** Reveals its `RevealItem` children one after another as the group enters view. */
export function RevealGroup({ children, className, amount = 0.2 }: RevealGroupProps) {
  const reduceMotion = useReducedMotion()

  if (reduceMotion) {
    return <div className={className}>{children}</div>
  }

  return (
    <motion.div
      className={className}
      variants={groupVariants}
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, amount }}
    >
      {children}
    </motion.div>
  )
}

/** A single staggered child of `RevealGroup` (also safe to use on its own). */
export function RevealItem({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  const reduceMotion = useReducedMotion()

  if (reduceMotion) {
    return <div className={className}>{children}</div>
  }

  return (
    <motion.div className={className} variants={itemVariants}>
      {children}
    </motion.div>
  )
}
