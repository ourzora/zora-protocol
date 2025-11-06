# Base Builder Notes on Zora Protocol

Zora’s approach to minting and marketplace logic makes it easy to turn ideas into onchain objects.  
From a Base builder’s view, the strongest part is how cleanly contracts compose with app-layer UX.

## What helps builders
- Clear separation of minting logic and marketplace interactions
- Good onchain event structure for indexing and analytics
- Documentation that points to reference deployments

## Small suggestions
1) A minimal “Base-ready” deployment walkthrough (testnet + mainnet) with exact RPC and verify steps.  
2) A short section on best practices for metadata pinning and URL fallbacks.  
3) One example contract that demonstrates primary mint → secondary trade → royalty observation end-to-end on **Base**.

**Why this matters**  
The faster someone can ship a working mint on Base, the faster culture compounds.  
Small docs/examples remove hesitation and get more creators onchain.
