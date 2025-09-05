import { useState } from "react";

interface ContractAddressProps {
  address: string;
  chain?: "base" | "base-sepolia" | "ethereum";
  label?: string;
}

const EXPLORER_URLS = {
  base: "https://basescan.org",
  "base-sepolia": "https://sepolia.basescan.org",
  ethereum: "https://etherscan.io",
};

export function ContractAddress({
  address,
  chain = "base",
  label,
}: ContractAddressProps) {
  const [copied, setCopied] = useState(false);
  const explorerUrl = EXPLORER_URLS[chain];
  const displayText = label || address;

  const copyToClipboard = async () => {
    await navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <span className="contract-address-wrapper">
      <a
        href={`${explorerUrl}/address/${address}`}
        target="_blank"
        rel="noopener noreferrer"
        title="View on explorer"
      >
        {displayText}
      </a>
      <button 
        onClick={copyToClipboard} 
        title={copied ? "Copied!" : "Copy address"}
        className="copy-button"
      >
        {copied ? "✓" : "📋"}
      </button>
    </span>
  );
}
