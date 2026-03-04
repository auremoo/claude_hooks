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

INPUT=$(cat)

TOOL_INFO=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    inp = d.get('tool_input', {})
    file_path = inp.get('file_path', '')
    content = inp.get('new_string', '') or inp.get('content', '')
    print(file_path)
    print(content)
except:
    print('')
    print('')
" "$INPUT" 2>/dev/null)

FILE_PATH=$(echo "$TOOL_INFO" | head -1)
CONTENT=$(echo "$TOOL_INFO" | tail -n +2)

if [ -z "$FILE_PATH" ] || [ -z "$CONTENT" ]; then
  exit 0
fi

# --- Validate protocol configs ---
WARNINGS=$(python3 -c "
import re, sys

file_path = sys.argv[1]
content = sys.argv[2]
warnings = []
content_lower = content.lower()

# ---- MODBUS ----
if 'modbus' in content_lower or 'register' in content_lower:
    # Check register addresses (valid: 0-65535 for most devices)
    for match in re.finditer(r'(?:register|address|offset)\s*[:=]\s*(\d+)', content, re.IGNORECASE):
        addr = int(match.group(1))
        if addr > 65535:
            warnings.append(f'Modbus register address {addr} exceeds 65535')
        if addr > 9999 and addr < 10000:
            warnings.append(f'Modbus address {addr} may cross coil/register boundary')

    # Check function codes
    for match in re.finditer(r'function[_\s]*code\s*[:=]\s*(\d+)', content, re.IGNORECASE):
        fc = int(match.group(1))
        valid_fcs = [1, 2, 3, 4, 5, 6, 15, 16, 22, 23]
        if fc not in valid_fcs:
            warnings.append(f'Modbus function code {fc} is non-standard')

    # Check unit ID
    for match in re.finditer(r'(?:unit[_\s]*id|slave[_\s]*id)\s*[:=]\s*(\d+)', content, re.IGNORECASE):
        uid = int(match.group(1))
        if uid > 247:
            warnings.append(f'Modbus unit ID {uid} exceeds max (247)')

# ---- OPC-UA ----
if 'opc' in content_lower or 'opcua' in content_lower:
    # Security mode None in production
    if re.search(r'security[_\s]*mode\s*[:=]\s*[\"\']*none', content, re.IGNORECASE):
        warnings.append('OPC-UA SecurityMode=None (no encryption/signing)')

    # Anonymous authentication
    if re.search(r'(anonymous|auth.*none|no.*auth)', content, re.IGNORECASE):
        if 'opc' in content_lower:
            warnings.append('OPC-UA anonymous authentication enabled')

    # Check endpoint URL format
    for match in re.finditer(r'opc\.tcp://([^:]+):(\d+)', content):
        port = int(match.group(2))
        if port == 4840:
            pass  # default port, OK
        elif port < 1024:
            warnings.append(f'OPC-UA using privileged port {port}')

# ---- MQTT ----
if 'mqtt' in content_lower:
    # QoS for critical data
    if re.search(r'qos\s*[:=]\s*0', content, re.IGNORECASE):
        if re.search(r'(alarm|safety|critical|emergency)', content, re.IGNORECASE):
            warnings.append('MQTT QoS 0 (fire-and-forget) used for critical/alarm data')

    # Wildcard subscriptions on root
    if re.search(r'subscribe.*[\"\'](#|\+/\+)', content, re.IGNORECASE):
        warnings.append('MQTT wildcard subscription on root topic (performance risk)')

    # No TLS
    if re.search(r'mqtt://', content) and not re.search(r'mqtts://|:8883', content):
        warnings.append('MQTT without TLS (use mqtts:// or port 8883)')

# ---- BACnet ----
if 'bacnet' in content_lower:
    # Object instance range
    for match in re.finditer(r'object[_\s]*instance\s*[:=]\s*(\d+)', content, re.IGNORECASE):
        instance = int(match.group(1))
        if instance > 4194303:
            warnings.append(f'BACnet object instance {instance} exceeds max (4194303)')

if warnings:
    print('; '.join(warnings[:4]))
else:
    print('')
" "$FILE_PATH" "$CONTENT" 2>/dev/null)

if [ -n "$WARNINGS" ]; then
  SAFE_WARNINGS=$(echo "$WARNINGS" | cut -c1-300 | sed 's/"/\\"/g')
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'PROTOCOL VALIDATION: ${SAFE_WARNINGS}'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
