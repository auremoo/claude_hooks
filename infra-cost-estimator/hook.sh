#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Infra Cost Estimator
# =============================================================================
# Warns before running infrastructure provisioning commands that may
# create billable cloud resources. Lists resources being created.
# =============================================================================

INPUT=$(cat)

COMMAND=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    inp = d.get('tool_input', {})
    print(inp.get('command', ''))
except:
    print('')
" "$INPUT" 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# --- Detect infra provisioning commands ---
WARNING=""

if echo "$COMMAND" | grep -qE 'terraform\s+apply'; then
  # Try to get terraform plan summary
  PLAN_SUMMARY=$(terraform plan -no-color 2>/dev/null | grep -E '(Plan:|will be|to add|to change|to destroy)' | head -5 | tr '\n' '; ')
  if [ -n "$PLAN_SUMMARY" ]; then
    WARNING="TERRAFORM APPLY: $PLAN_SUMMARY"
  else
    WARNING="TERRAFORM APPLY: About to provision cloud resources. Run 'terraform plan' first to review."
  fi

elif echo "$COMMAND" | grep -qE 'terraform\s+destroy'; then
  WARNING="TERRAFORM DESTROY: About to destroy ALL managed infrastructure resources!"

elif echo "$COMMAND" | grep -qE 'pulumi\s+up'; then
  WARNING="PULUMI UP: About to provision cloud resources. Review the preview first."

elif echo "$COMMAND" | grep -qE 'pulumi\s+destroy'; then
  WARNING="PULUMI DESTROY: About to destroy ALL managed infrastructure resources!"

elif echo "$COMMAND" | grep -qE 'aws\s+cloudformation\s+(create-stack|update-stack|deploy)'; then
  WARNING="CLOUDFORMATION DEPLOY: About to create/update a CloudFormation stack with billable resources."

elif echo "$COMMAND" | grep -qE 'aws\s+cloudformation\s+delete-stack'; then
  WARNING="CLOUDFORMATION DELETE: About to delete a CloudFormation stack and all its resources!"

elif echo "$COMMAND" | grep -qE 'cdk\s+deploy'; then
  WARNING="CDK DEPLOY: About to deploy AWS CDK stack with potentially billable resources."

elif echo "$COMMAND" | grep -qE 'gcloud\s+(compute|sql|container|run)\s+.*create'; then
  WARNING="GCLOUD CREATE: About to create Google Cloud resources (billable)."

elif echo "$COMMAND" | grep -qE 'az\s+(vm|aks|sql|storage|webapp)\s+create'; then
  WARNING="AZURE CREATE: About to create Azure resources (billable)."

elif echo "$COMMAND" | grep -qE 'helm\s+install|helm\s+upgrade'; then
  WARNING="HELM INSTALL/UPGRADE: About to deploy Kubernetes resources that may provision cloud infra."
fi

if [ -n "$WARNING" ]; then
  SAFE_WARNING=$(echo "$WARNING" | cut -c1-300 | sed 's/"/\\"/g')
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'INFRA COST: ${SAFE_WARNING}'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
