#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Protocol Validator
# =============================================================================
# Validates industrial protocol configurations for common issues:
# - Modbus: register address ranges, function codes
# - OPC-UA: security mode, endpoint URLs
# - MQTT: QoS levels, topic naming
# - BACnet: object identifiers
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local PYCODE

  # Fast exit (no python) when the tool call mentions none of the protocols
  shopt -s nocasematch
  [[ $INPUT == *modbus* || $INPUT == *register* || $INPUT == *opc* || $INPUT == *mqtt* || $INPUT == *bacnet* ]] || return 0
  shopt -u nocasematch

  IFS= read -r -d '' PYCODE <<'PYEOF'
if not PATH or not CONTENT:
    sys.exit(0)
content = CONTENT
content_lower = content.lower()
warnings = []

# ---- MODBUS ----
if 'modbus' in content_lower or 'register' in content_lower:
    # Register addresses (valid: 0-65535 for most devices)
    for m in re.finditer(r'(?:register|address|offset)\s*[:=]\s*(\d+)', content, re.I):
        addr = int(m.group(1))
        if addr > 65535:
            warnings.append('Modbus register address %d exceeds 65535' % addr)
    # Function codes
    for m in re.finditer(r'function[_\s]*code\s*[:=]\s*(\d+)', content, re.I):
        fc = int(m.group(1))
        if fc not in (1, 2, 3, 4, 5, 6, 15, 16, 22, 23):
            warnings.append('Modbus function code %d is non-standard' % fc)
    # Unit ID
    for m in re.finditer(r'(?:unit[_\s]*id|slave[_\s]*id)\s*[:=]\s*(\d+)', content, re.I):
        uid = int(m.group(1))
        if uid > 247:
            warnings.append('Modbus unit ID %d exceeds max (247)' % uid)

# ---- OPC-UA ----
if 'opc' in content_lower:
    # Security mode None in production
    if re.search(r'security[_\s]*mode\s*[:=]\s*["\']*none', content, re.I):
        warnings.append('OPC-UA SecurityMode=None (no encryption/signing)')
    # Anonymous authentication
    if re.search(r'(anonymous|auth.*none|no.*auth)', content, re.I):
        warnings.append('OPC-UA anonymous authentication enabled')
    # Endpoint URL: 4840 is the default port
    for m in re.finditer(r'opc\.tcp://([^:]+):(\d+)', content):
        port = int(m.group(2))
        if port < 1024:
            warnings.append('OPC-UA using privileged port %d' % port)

# ---- MQTT ----
if 'mqtt' in content_lower:
    # QoS for critical data
    if re.search(r'qos\s*[:=]\s*0', content, re.I) and \
       re.search(r'(alarm|safety|critical|emergency)', content, re.I):
        warnings.append('MQTT QoS 0 (fire-and-forget) used for critical/alarm data')
    # Wildcard subscriptions on root
    if re.search(r'subscribe.*["\'](#|\+/\+)', content, re.I):
        warnings.append('MQTT wildcard subscription on root topic (performance risk)')
    # No TLS
    if re.search(r'mqtt://', content) and not re.search(r'mqtts://|:8883', content):
        warnings.append('MQTT without TLS (use mqtts:// or port 8883)')

# ---- BACnet ----
if 'bacnet' in content_lower:
    # Object instance range
    for m in re.finditer(r'object[_\s]*instance\s*[:=]\s*(\d+)', content, re.I):
        instance = int(m.group(1))
        if instance > 4194303:
            warnings.append('BACnet object instance %d exceeds max (4194303)' % instance)

if warnings:
    ask('PROTOCOL VALIDATION: ' + '; '.join(warnings[:4])[:300])
PYEOF

  run_py "$PYCODE"
  return 0
}

main
