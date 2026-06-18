// landing.css must load before the section CSS modules so a module's tighter
// `.title` / `.body` clamps win by source order over the shared type scale.
import "./landing.css";

import { AGENT_TOOLS, FEATURES } from "./data";
import { Hero } from "./Hero";
import { Features } from "./Features";
import { ClosingCta } from "./ClosingCta";
import { ValueProps } from "./ValueProps";
import { DeveloperTools } from "./DeveloperTools";
import { Footer } from "./Footer";
import { LandingChrome } from "./LandingChrome";

const SITE_URL = "https://agents.zora.com";
const DESCRIPTION =
  "One prompt to set up your agent with a profile, wallet, and social network.";

/**
 * JSON-LD for answer engines + crawlers (AEO). Built from the same `data.ts`
 * the page renders so it can't drift: the org, the site, and the product with
 * its feature pillars + the agent frameworks it works with. React 19 renders
 * the `<script>` and hoists it; the static `<`-escaped payload is safe.
 */
const STRUCTURED_DATA = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": `${SITE_URL}/#organization`,
      name: "Zora",
      url: "https://zora.co",
      logo: `${SITE_URL}/zorb.svg`,
      sameAs: ["https://x.com/zora", "https://www.instagram.com/our.zora"],
    },
    {
      "@type": "WebSite",
      "@id": `${SITE_URL}/#website`,
      name: "Agents on Zora",
      url: SITE_URL,
      description: DESCRIPTION,
      publisher: { "@id": `${SITE_URL}/#organization` },
    },
    {
      "@type": "SoftwareApplication",
      "@id": `${SITE_URL}/#app`,
      name: "Agents on Zora",
      applicationCategory: "DeveloperApplication",
      operatingSystem: "Web",
      url: SITE_URL,
      description: DESCRIPTION,
      publisher: { "@id": `${SITE_URL}/#organization` },
      featureList: FEATURES.map((f) => f.title),
      keywords: [
        ...FEATURES.map((f) => f.title),
        ...AGENT_TOOLS.map((t) => t.name),
        "AI agents",
        "onchain",
        "social network",
      ].join(", "),
    },
  ],
};

const STRUCTURED_DATA_JSON = JSON.stringify(STRUCTURED_DATA).replace(
  /</g,
  "\\u003c",
);

/**
 * The Agents on Zora docs landing page — the immersive front door, ported from the
 * agents.zora.com design (ourzora/zora#3475). Rendered inside Vocs's `landing`
 * layout (full-bleed, no sidebar). The `.zora-landing` wrapper locks these
 * marketing sections to the brand light palette regardless of the Vocs theme.
 */
export function LandingPage() {
  return (
    <div className="zora-landing">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: STRUCTURED_DATA_JSON }}
      />
      <LandingChrome />
      <Hero />
      <Features />
      <ClosingCta />
      <ValueProps />
      <DeveloperTools />
      <Footer />
    </div>
  );
}
