"use client";
import { useEffect, useRef, type ReactNode } from "react";

export function HeroGrid({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        ref.current?.classList.add("hero-loaded");
      });
    });
  }, []);
  return (
    <div
      ref={ref}
      className="hero-grid"
      style={{ display: "flex", flexDirection: "column", gap: "1.5rem" }}
    >
      {children}
    </div>
  );
}
