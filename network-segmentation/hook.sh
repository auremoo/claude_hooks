#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Network Segmentation
# =============================================================================
# Detects potential IT/OT network boundary violations in code and configs.
# Prevents direct access from IT zone to OT/Safety zones per IEC 62443.
#
# Each IP address belongs to the most specific zone containing it: with
# IT = 10.0.0.0/8 and OT = 10.135.0.0/16, the address 10.135.1.1 is OT only.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local PYCODE ZONES_FILE

  # Fast exit (no python) when the tool call contains nothing looking like an IPv4
  [[ $INPUT =~ [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ]] || return 0

  ZONES_FILE="$HOOK_DIR/network_zones.txt"
  [ -f "$ZONES_FILE" ] || return 0

  IFS= read -r -d '' PYCODE <<'PYEOF'
import ipaddress

content = CONTENT or _s(INP.get('command'))
if not content:
    sys.exit(0)

# Zone definitions: ZONE_NAME | IP_RANGE | SECURITY_LEVEL
networks = []
for rule in rules(ARGS[0]):
    if ' -> ' in rule:
        continue  # cross-zone rules are documentation only
    parts = [p.strip() for p in rule.split('|')]
    if len(parts) >= 2:
        try:
            networks.append((ipaddress.ip_network(parts[1], strict=False), parts[0]))
        except ValueError:
            sys.stderr.write('claude-hooks: invalid IP range %r\n' % parts[1])
if not networks:
    sys.exit(0)

# Classify every IP of the content by zone (most specific network wins)
found_zones = set()
for ip_str in set(re.findall(r'\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b', content)):
    try:
        ip = ipaddress.ip_address(ip_str)
    except ValueError:
        continue
    containing = [(net.prefixlen, zone) for net, zone in networks
                  if ip.version == net.version and ip in net]
    if containing:
        found_zones.add(max(containing)[1])

warnings = []
# Cross-zone access
if 'IT' in found_zones and 'OT' in found_zones:
    warnings.append('IT and OT IPs in same context (cross-zone access)')
if 'IT' in found_zones and 'SAFETY' in found_zones:
    warnings.append('IT and SAFETY IPs in same context (CRITICAL violation)')
if 'OT' in found_zones and 'SAFETY' in found_zones:
    warnings.append('OT and SAFETY IPs in same context (verify conduit)')
# SAFETY zone access in general code
if 'SAFETY' in found_zones:
    warnings.append('Code references SAFETY zone IPs (SIL-rated access only)')

if warnings:
    ask('NETWORK SEGMENTATION: %s -- ISA/IEC 62443 zone boundary violation.'
        % '; '.join(warnings[:3])[:300])
PYEOF

  run_py "$PYCODE" "$ZONES_FILE"
  return 0
}

main
