#!/usr/bin/env python3
import re

# Extract gas measurements from local results
local_data = {}
with open('gas_results_after.log', 'r') as f:
    for line in f:
        match = re.search(r'(\w+)_GAS: (\d+)', line)
        if match:
            local_data[match.group(1)] = int(match.group(2))

# Extract gas measurements from fork results  
fork_data = {}
with open('gas_results_fork_with_logs.log', 'r') as f:
    for line in f:
        match = re.search(r'(\w+)_GAS: (\d+)', line)
        if match:
            fork_data[match.group(1)] = int(match.group(2))

# Create comparison table
print("=== Gas Measurement Comparison: Local (Anvil) vs Tenderly Fork (Base Mainnet) ===\n")
print(f"{'Test Scenario':<60} | {'Local Gas':>12} | {'Fork Gas':>12} | {'Difference':>12} | {'% Diff':>8}")
print("-" * 120)

for key in sorted(local_data.keys()):
    if key in fork_data:
        local_gas = local_data[key]
        fork_gas = fork_data[key]
        diff = fork_gas - local_gas
        pct_diff = (diff / local_gas * 100) if local_gas > 0 else 0
        
        # Format test name
        test_name = key.replace('_', ' ').title()
        
        print(f"{test_name:<60} | {local_gas:>12,} | {fork_gas:>12,} | {diff:>+12,} | {pct_diff:>+7.2f}%")

print("\n=== Summary Statistics ===")
differences = [(fork_data[k] - local_data[k]) for k in local_data if k in fork_data]
pct_differences = [(fork_data[k] - local_data[k]) / local_data[k] * 100 for k in local_data if k in fork_data and local_data[k] > 0]

print(f"Tests compared: {len(differences)}")
print(f"Average absolute difference: {sum(abs(d) for d in differences) / len(differences):,.0f} gas")
print(f"Average percentage difference: {sum(abs(p) for p in pct_differences) / len(pct_differences):.3f}%")
print(f"Max percentage difference: {max(abs(p) for p in pct_differences):.3f}%")
print(f"Min percentage difference: {min(abs(p) for p in pct_differences):.3f}%")

# Check if measurements are consistent (within 2%)
consistent = all(abs(p) < 2.0 for p in pct_differences)
print(f"\n✅ All measurements within 2% variance: {consistent}")
