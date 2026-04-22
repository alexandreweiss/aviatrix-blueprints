# =============================================================================
# Aviatrix DCF MITM CA trust-store distribution.
#
# The CA PEM is fetched from the controller (/v2.5/api/dcf/mitm-ca) and
# written to avx-root-ca.pem by scripts/fetch-avx-ca.sh (idempotent).
#
# Distribution paths:
#   1. Runtime container: baked into the image at build time via the
#      Dockerfile (/usr/local/share/ca-certificates/avx-dcf-mitm.crt).
#      Reflected in the src-hash in agent.tf so rotations force a rebuild.
#
#   2. Browser + Code Interpreter (v2 primitives, deploy-on-demand): the
#      AgentCore Start*Session APIs accept a `certificates` parameter that
#      takes an ARN to a Secrets Manager secret containing the PEM. The
#      secret resource below exists today so the ARN is stable and known
#      to downstream TF configs that add Browser / Code Interpreter.
#
#   3. Workloads outside AgentCore that happen to live in a VCA-governed
#      spoke can pull the PEM from the same Secrets Manager secret as
#      part of their own bootstrap.
# =============================================================================

resource "aws_secretsmanager_secret" "avx_mitm_ca" {
  name        = "${local.name_prefix}-avx-mitm-ca"
  description = "Aviatrix DCF MITM root CA (public cert only). Distributed to AgentCore Browser / Code Interpreter trust stores."
  # Not sensitive: the PEM is the public half of a CA cert. The private key
  # stays on the Aviatrix controller / spoke gateway.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "avx_mitm_ca" {
  secret_id     = aws_secretsmanager_secret.avx_mitm_ca.id
  secret_string = file("${path.module}/avx-root-ca.pem")
}

# Grant the runtime execution role read access (preemptive; not used in v1
# but Browser / Code Interpreter service roles will need this once added).
data "aws_iam_policy_document" "read_avx_mitm_ca" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.avx_mitm_ca.arn]
  }
}

resource "aws_iam_role_policy" "runtime_read_avx_mitm_ca" {
  name   = "read-avx-mitm-ca"
  role   = aws_iam_role.agentcore_runtime.id
  policy = data.aws_iam_policy_document.read_avx_mitm_ca.json
}
