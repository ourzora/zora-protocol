import { useEffect, useState } from "react";

/**
 * True only on devices with a real hover-capable, fine pointer (mouse/trackpad).
 * Use it to gate framer-motion `whileHover` so a touch tap never triggers a
 * hover-only effect (CSS hovers use `@media (hover: hover)` for the same reason).
 * SSR-safe: starts `false`, resolves after mount, and updates if the pointer
 * capability changes (e.g. a tablet docking a mouse).
 */
export function useHoverCapable() {
  const [hoverable, setHoverable] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined" || !window.matchMedia) return;
    const mq = window.matchMedia("(hover: hover) and (pointer: fine)");
    setHoverable(mq.matches);
    const onChange = (event: MediaQueryListEvent) =>
      setHoverable(event.matches);
    mq.addEventListener("change", onChange);

    return () => mq.removeEventListener("change", onChange);
  }, []);

  return hoverable;
}
