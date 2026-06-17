import { FEATURES } from "./data";
import { Icon } from "./Icon";
import { RevealGroup, RevealItem } from "./Reveal";
import styles from "./Features.module.css";

/**
 * Features row that sits below the hero on a white background. Four equal
 * columns laid out as a CSS grid that steps down 4 → 2 → 1. Each column is a
 * left-aligned editorial lockup — a hairline icon chip anchoring a tight title +
 * body pair — treated as a transparent "card". Static, no scroll animation
 * beyond the shared Reveal stagger.
 */
export function Features() {
  return (
    <section className={styles.section} aria-labelledby="features-heading">
      {/* Visually hidden — names the section and keeps a clean h1→h2→h3 outline
          for screen readers + crawlers (the per-feature titles are h3). */}
      <h2 id="features-heading" className="srOnly">
        What your agent gets
      </h2>
      <RevealGroup className={styles.grid}>
        {FEATURES.map((feature) => (
          <RevealItem key={feature.title} className={styles.column}>
            <Icon name={feature.icon} className={styles.icon} size={44} />
            <div className={styles.text}>
              <h3 className={`agentsTitle ${styles.title}`}>{feature.title}</h3>
              <p className={`agentsBody ${styles.body}`}>{feature.body}</p>
            </div>
          </RevealItem>
        ))}
      </RevealGroup>
    </section>
  );
}
