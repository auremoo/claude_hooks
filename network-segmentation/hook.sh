#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Network Segmentation
# =============================================================================
# Detects potential IT/OT network boundary violations in code and configs.
# Prevents direct access from IT zone to OT/Safety zones per IEC 62443.
# =============================================================================

INPUT=$(cat)

TOOL_INFO=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    inp = d.get('tool_input', {})
    file_path = inp.get('file_path', '')
    content = inp.get('new_string', '') or inp.get('content', '') or inp.get('command', '')
    print(file_path)
    print(content)
except:
    print('')
    print('')
" "$INPUT" 2>/dev/null)

FILE_PATH=$(echo "$TOOL_INFO" | head -1)
CONTENT=$(echo "$TOOL_INFO" | tail -n +2)

if [ -z "$CONTENT" ]; then
  exit 0
fi

# --- Load network zones ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ZONES_FILE="$HOOK_DIR/network_zones.txt"

if [ ! -f "$ZONES_FILE" ]; then
  exit 0
fi

WARNINGS=$(python3 -c "
import re, sys, ipaddress

zones_file = sys.argv[1]
content = sys.argv[2]

# Parse zone definitions
zones = {}
with open(zones_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if ' -> ' in line:
            continue  # Skip cross-zone rules
        parts = [p.strip() for p in line.split('|')]
        if len(parts) >= 2:
            zone_name = parts[0]
            ip_range = parts[1]
            try:
                network = ipaddress.ip_network(ip_range, strict=False)
                if zone_name not in zones:
                    zones[zone_name] = []
                zones[zone_name].append(network)
            except:
                pass

if not zones:
    sys.exit(0)

# Find all IP addresses in content
ip_pattern = r'\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b'
found_ips = re.findall(ip_pattern, content)

if not found_ips:
    sys.exit(0)

# Classify IPs by zone
warnings = []
found_zones = set()

for ip_str in found_ips:
    try:
        ip = ipaddress.ip_address(ip_str)
        for zone_name, networks in zones.items():
            for network in networks:
                if ip in network:
                    found_zones.add(zone_name)
    except:
        continue

# Check for cross-zone access
if 'IT' in found_zones and 'OT' in found_zones:
    warnings.append('IT and OT IPs in same context (cross-zone access)')
if 'IT' in found_zones and 'SAFETY' in found_zones:
    warnings.append('IT and SAFETY IPs in same context (CRITICAL violation)')
if 'OT' in found_zones and 'SAFETY' in found_zones:
    warnings.append('OT and SAFETY IPs in same context (verify conduit)')

# Check for SAFETY zone access in general code
if 'SAFETY' in found_zones:
    warnings.append('Code references SAFETY zone IPs (SIL-rated access only)')

if warnings:
    print('; '.join(warnings[:3]))
else:
    print('')
" "$ZONES_FILE" "$CONTENT" 2>/dev/null)

if [ -n "$WARNINGS" ]; then
  SAFE_WARNINGS=$(echo "$WARNINGS" | cut -c1-300 | sed 's/"/\\"/g')
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'NETWORK SEGMENTATION: ${SAFE_WARNINGS} -- ISA/IEC 62443 zone boundary violation.'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
