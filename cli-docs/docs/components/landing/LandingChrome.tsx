import { useEffect } from "react";

/**
 * Drives the Vocs top-nav appearance on the landing page: transparent while the
 * hero burst is behind it, solid once the reader scrolls past the hero (so the
 * nav never floats over — and collide with — the white content sections).
 *
 * Sets `data-landing-nav="top" | "solid"` on <html>; the matching CSS lives in
 * docs/styles.css. Renders nothing. The default (no attribute / "top") is
 * transparent, so there's no white-bar flash before this mounts.
 */
export function LandingChrome() {
  useEffect(() => {
    const root = document.documentElement;
    // The nav switches to solid a touch before the hero is fully gone — when
    // the hero's bottom rises to within ~one nav-height of the top.
    const NAV_OFFSET = 64;

    let frame = 0;
    const update = () => {
      frame = 0;
      const hero = document.querySelector<HTMLElement>(
        'section[aria-labelledby="hero-heading"]',
      );
      const heroBottom = hero ? hero.getBoundingClientRect().bottom : 0;
      root.dataset.landingNav = heroBottom <= NAV_OFFSET ? "solid" : "top";
    };
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };

    update();
    window.addEventListener("scroll", onScroll, { passive: true, capture: true });
    window.addEventListener("resize", onScroll, { passive: true });
    return () => {
      if (frame) cancelAnimationFrame(frame);
      window.removeEventListener("scroll", onScroll, { capture: true });
      window.removeEventListener("resize", onScroll);
      delete root.dataset.landingNav;
    };
  }, []);

  return null;
}
