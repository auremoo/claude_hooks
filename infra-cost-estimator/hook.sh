#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Infra Cost Estimator
# =============================================================================
# Warns before running infrastructure provisioning commands that may
# create (or destroy) billable cloud resources.
#
# The hook never runs `terraform plan` itself: a plan needs credentials, may
# lock the state and takes far longer than a hook timeout allows.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local COMMAND REPLY S WARNING

  json_str command || return 0
  COMMAND=$REPLY
  [ -n "$COMMAND" ] || return 0

  S='[[:space:]]+'
  is() { [[ $COMMAND =~ $1 ]]; }

  # --- Detect infra provisioning commands ---
  WARNING=""
  if   is "terraform${S}apply";   then WARNING="TERRAFORM APPLY: About to provision cloud resources. Run 'terraform plan' first to review."
  elif is "terraform${S}destroy"; then WARNING="TERRAFORM DESTROY: About to destroy ALL managed infrastructure resources!"
  elif is "pulumi${S}up";         then WARNING="PULUMI UP: About to provision cloud resources. Review the preview first."
  elif is "pulumi${S}destroy";    then WARNING="PULUMI DESTROY: About to destroy ALL managed infrastructure resources!"
  elif is "aws${S}cloudformation${S}(create-stack|update-stack|deploy)"; then
    WARNING="CLOUDFORMATION DEPLOY: About to create/update a CloudFormation stack with billable resources."
  elif is "aws${S}cloudformation${S}delete-stack"; then
    WARNING="CLOUDFORMATION DELETE: About to delete a CloudFormation stack and all its resources!"
  elif is "cdk${S}deploy";        then WARNING="CDK DEPLOY: About to deploy AWS CDK stack with potentially billable resources."
  elif is "gcloud${S}(compute|sql|container|run)${S}.*create"; then
    WARNING="GCLOUD CREATE: About to create Google Cloud resources (billable)."
  elif is "az${S}(vm|aks|sql|storage|webapp)${S}create"; then
    WARNING="AZURE CREATE: About to create Azure resources (billable)."
  elif is "helm${S}(install|upgrade)"; then
    WARNING="HELM INSTALL/UPGRADE: About to deploy Kubernetes resources that may provision cloud infra."
  fi

  [ -n "$WARNING" ] && emit_pre ask "INFRA COST: $WARNING"
  return 0
}

main
