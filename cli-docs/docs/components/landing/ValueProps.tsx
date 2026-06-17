import { VALUE_PROPS } from "./data";
import { RevealGroup, RevealItem } from "./Reveal";
import styles from "./ValueProps.module.css";

/**
 * Value-prop grid on a white background. A centered 2×2 grid of {title, body},
 * each cell centered, that collapses to a single column on narrow viewports.
 * Static — no scroll animation.
 */
export function ValueProps() {
  return (
    <section className={styles.section} aria-labelledby="valueprops-heading">
      {/* Visually hidden — names the section and keeps a clean h1→h2→h3 outline
          for screen readers + crawlers (the per-prop titles are h3). */}
      <h2 id="valueprops-heading" className="srOnly">
        Why build on Zora
      </h2>
      <RevealGroup className={styles.grid}>
        {VALUE_PROPS.map((prop) => (
          <RevealItem key={prop.title} className={styles.cell}>
            <div className={styles.text}>
              <h3 className={`agentsTitle ${styles.title}`}>{prop.title}</h3>
              <p className={`agentsBody ${styles.body}`}>{prop.body}</p>
            </div>
          </RevealItem>
        ))}
      </RevealGroup>
    </section>
  );
}
