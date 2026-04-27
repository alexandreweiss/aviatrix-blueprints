# Deployment Workflow

Step-by-step guide for deploying all three Kubernetes blueprint patterns.

## Prerequisites

### Credentials

```bash
# Aviatrix Controller
export AVIATRIX_CONTROLLER_IP="<controller-ip>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<password>"

# AWS (STS session or access keys)
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

# Account name in Aviatrix (Patterns A & B)
export TF_VAR_aviatrix_aws_account_name="lab-test-aws"

# Account name in Aviatrix (Pattern C — different variable name)
export TF_VAR_aws_account_name="lab-test-aws"
```

### Tools

| Tool | Minimum |
|---|---|
| Terraform | >= 1.5 |
| AWS CLI | >= 2.0 |
| kubectl | >= 1.28 |
| Helm | >= 3.0 |

### AWS Service Quotas (per region)

| Quota | Pattern A | Pattern B | Pattern C |
|---|---|---|---|
| VPCs | 6 | 3 | 5 |
| Elastic IPs | 12 | 4 | 10 |
| EKS Clusters | 3 | 1 | 2 |

Request increases before deploying if needed:
```bash
aws service-quotas request-service-quota-increase \
  --service-code vpc --quota-code L-F678F1CE --desired-value 20 --region <region>
```

---

## Architecture Recommendation Toggles

All patterns include optional hardening add-ons. All default to `false`.

```hcl
# nodes/*/terraform.tfvars or -var flags

# Security
enable_network_policy   = true   # Calico NetworkPolicy (defense-in-depth)
enable_gatekeeper       = true   # OPA Gatekeeper admission control
enable_external_secrets = true   # AWS Secrets Manager → Kubernetes Secrets
enable_falco            = true   # Runtime threat detection

# Observability
enable_prometheus_stack = true   # Prometheus + Grafana + alerting
enable_fluent_bit       = true   # Log aggregation to CloudWatch

# Resilience
enable_node_termination_handler = true  # Required for SPOT nodes
enable_cluster_autoscaler       = true  # Dynamic node scaling
enable_velero                   = true  # Cluster backup to S3
```

**Suggested profiles:**

| Profile | Toggles |
|---|---|
| Demo/Lab | All defaults (`false`) |
| Minimum Prod | `network_policy`, `node_termination_handler`, `cluster_autoscaler` |
| Full Hardening | All `true` |

---

## Pattern A: k8s-cluster-aas

**Region:** us-west-2 · **Architecture:** 3 dedicated EKS clusters, VPC-level DCF isolation

```bash
BASE=blueprints/k8s-cluster-aas/aws
```

### Deploy

```bash
# Layer 1: Network (~8 min)
terraform -chdir=$BASE/network init
terraform -chdir=$BASE/network apply -var="aviatrix_aws_account_name=lab-test-aws" -auto-approve

# Layer 2: Clusters — parallel (~15 min)
for team in team-a team-b team-c; do
  terraform -chdir=$BASE/clusters/$team init
  terraform -chdir=$BASE/clusters/$team apply \
    -var="aviatrix_aws_account_name=lab-test-aws" -auto-approve &
done && wait

# Layer 3: Nodes — parallel (~8 min)
for team in team-a team-b team-c; do
  terraform -chdir=$BASE/nodes/$team init
  terraform -chdir=$BASE/nodes/$team apply -auto-approve &
done && wait
```

### Configure kubectl

```bash
# Cluster names include the random suffix (e.g., caas-4462-team-a)
PREFIX=$(terraform -chdir=$BASE/network output -raw name_prefix)
for team in team-a team-b team-c; do
  aws eks update-kubeconfig --name "${PREFIX}-${team}" --alias $team --region us-west-2
done
```

### Test

```bash
# Deploy test containers
for team in team-a team-b team-c; do
  kubectl apply -f $BASE/k8s-apps/traffic-test/$team/
done

# Run automated test suite (8 tests, expect 8/8 pass)
cd $BASE/k8s-apps/traffic-test
./run-tests.sh team-a team-b team-c
```

### Destroy

```bash
for team in team-c team-b team-a; do
  terraform -chdir=$BASE/nodes/$team destroy -auto-approve &
done && wait

for team in team-c team-b team-a; do
  terraform -chdir=$BASE/clusters/$team destroy \
    -var="aviatrix_aws_account_name=lab-test-aws" -auto-approve &
done && wait

terraform -chdir=$BASE/network destroy -var="aviatrix_aws_account_name=lab-test-aws" -auto-approve
```

---

## Pattern B: k8s-namespace-aas

**Region:** us-east-1 · **Architecture:** 1 shared EKS cluster, namespace-level DCF + Calico isolation

```bash
BASE=blueprints/k8s-namespace-aas/aws
```

### Deploy

```bash
# Layer 1: Network (~8 min)
terraform -chdir=$BASE/network init
terraform -chdir=$BASE/network apply -var="aviatrix_aws_account_name=lab-test-aws" -auto-approve

# Layer 2: Cluster (~15 min)
terraform -chdir=$BASE/clusters/shared init
terraform -chdir=$BASE/clusters/shared apply \
  -var="aviatrix_aws_account_name=lab-test-aws" -auto-approve

# Layer 3: Nodes (~8 min)
terraform -chdir=$BASE/nodes/shared init
terraform -chdir=$BASE/nodes/shared apply -auto-approve

# Layer 4: NetworkPolicy CRDs
CLUSTER=$(terraform -chdir=$BASE/network output -raw shared_cluster_name)
aws eks update-kubeconfig --name $CLUSTER --alias naas-shared --region us-east-1
kubectl --context naas-shared apply -f $BASE/k8s-apps/dcf-crd/network-policies.yaml
```

### Test

```bash
# Create test pods per namespace
for ns in team-a team-b team-c; do
  kubectl --context naas-shared create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
  kubectl --context naas-shared -n $ns run nginx --image=nginx:alpine --port=80 --restart=Never
  kubectl --context naas-shared -n $ns run netshoot \
    --image=nicolaka/netshoot --command -- sleep infinity --restart=Never
  kubectl --context naas-shared -n $ns expose pod nginx \
    --port=443 --target-port=80 --name="${ns}-svc"
done

# Wait for pods
for ns in team-a team-b team-c; do
  kubectl --context naas-shared wait --for=condition=Ready pod/netshoot -n $ns --timeout=60s
done

# Expected: team-a→team-b PASS, team-a→team-c BLOCKED, team-c→team-b BLOCKED
kubectl --context naas-shared -n team-a exec netshoot -- curl -m5 http://team-b-svc.team-b.svc.cluster.local:443
kubectl --context naas-shared -n team-a exec netshoot -- curl -m5 http://team-c-svc.team-c.svc.cluster.local:443
```

### Destroy

```bash
kubectl --context naas-shared delete -f $BASE/k8s-apps/dcf-crd/ --ignore-not-found
terraform -chdir=$BASE/nodes/shared destroy -auto-approve
terraform -chdir=$BASE/clusters/shared destroy -var="aviatrix_aws_account_name=lab-test-aws" -auto-approve
terraform -chdir=$BASE/network destroy -var="aviatrix_aws_account_name=lab-test-aws" -auto-approve
```

---

## Pattern C: k8s-prod-nonprod-hybrid (Recommended)

**Region:** us-east-2 · **Architecture:** 2 EKS clusters (prod/nonprod), two-layer DCF isolation

```bash
BASE=blueprints/k8s-prod-nonprod-hybrid/aws
```

### Deploy

```bash
# Layer 1: Network (~8 min)
terraform -chdir=$BASE/network init
terraform -chdir=$BASE/network apply -var="aws_account_name=lab-test-aws" -auto-approve

# Layer 2: Clusters — parallel (~15 min)
for env in prod nonprod; do
  terraform -chdir=$BASE/clusters/$env init
  terraform -chdir=$BASE/clusters/$env apply \
    -var="aviatrix_aws_account_name=lab-test-aws" -auto-approve &
done && wait

# Layer 3: Nodes — parallel (~8 min)
for env in prod nonprod; do
  terraform -chdir=$BASE/nodes/$env init
  terraform -chdir=$BASE/nodes/$env apply -auto-approve &
done && wait

# Layer 4: Namespaces + CRDs
PREFIX=$(terraform -chdir=$BASE/network output -raw name_prefix 2>/dev/null || echo "pc2")
aws eks update-kubeconfig --name "${PREFIX}-prod" --alias pc2-prod --region us-east-2
aws eks update-kubeconfig --name "${PREFIX}-nonprod" --alias pc2-nonprod --region us-east-2

kubectl --context pc2-prod apply -f $BASE/k8s-apps/dcf-crd/prod-namespaces.yaml
kubectl --context pc2-prod apply -f $BASE/k8s-apps/dcf-crd/firewallpolicy-prod.yaml
kubectl --context pc2-nonprod apply -f $BASE/k8s-apps/dcf-crd/nonprod-namespaces.yaml
kubectl --context pc2-nonprod apply -f $BASE/k8s-apps/dcf-crd/firewallpolicy-nonprod.yaml
```

### Test

```bash
PROD_IP=$(kubectl --context pc2-prod -n default get pod nginx -o jsonpath='{.status.podIP}' 2>/dev/null)
NONPROD_IP=$(kubectl --context pc2-nonprod -n default get pod nginx -o jsonpath='{.status.podIP}' 2>/dev/null)

# prod → nonprod: BLOCKED (DENY rule 10)
kubectl --context pc2-prod exec netshoot -- curl -m10 http://$NONPROD_IP:80

# nonprod → prod: BLOCKED (DENY rule 11)
kubectl --context pc2-nonprod exec netshoot -- curl -m10 http://$PROD_IP:80

# prod egress: PASS
kubectl --context pc2-prod exec netshoot -- curl -m10 https://registry.k8s.io
```

### Destroy

```bash
kubectl --context pc2-prod delete -f $BASE/k8s-apps/dcf-crd/ --ignore-not-found
kubectl --context pc2-nonprod delete -f $BASE/k8s-apps/dcf-crd/ --ignore-not-found

for env in prod nonprod; do
  terraform -chdir=$BASE/nodes/$env destroy -auto-approve &
done && wait

for env in prod nonprod; do
  terraform -chdir=$BASE/clusters/$env destroy \
    -var="aviatrix_aws_account_name=lab-test-aws" -auto-approve &
done && wait

terraform -chdir=$BASE/network destroy -var="aws_account_name=lab-test-aws" -auto-approve
```

---

## Validation Checklist

### Network Layer
- [ ] Transit Gateway visible in CoPilot Topology
- [ ] All Spoke Gateways attached and green
- [ ] SNAT policies active on each spoke
- [ ] DCF enabled: `aviatrix_distributed_firewalling_config` applied

### DCF
- [ ] DCF policy group created (`aviatrix_dcf_policy_group`)
- [ ] Ruleset attached with correct priorities
- [ ] SmartGroups showing members (VPC-type or K8s namespace-type)
- [ ] WebGroups resolving (EKS required services, docker.io)
- [ ] Geo-blocking and ThreatIQ active

### Kubernetes
- [ ] EKS clusters ACTIVE, nodes Ready
- [ ] Aviatrix controller can inventory cluster (check CoPilot > Kubernetes)
- [ ] k8s-firewall Helm chart installed (`kubectl get crd | grep aviatrix`)
- [ ] Calico running: `kubectl get pods -n calico-system`
- [ ] Namespaces created (Pattern B and C)
- [ ] NetworkPolicies applied (Pattern B)

### Traffic Tests
- [ ] Permitted cross-cluster/namespace flows: working
- [ ] Denied flows: blocked (timeout, not refused)
- [ ] Approved egress (registry.k8s.io): working
- [ ] Default deny internet: blocked
- [ ] Pattern C: nonprod → prod DENIED both directions

---

## Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| `AVXERR-DFW-0043` attachment conflict | Multiple blueprints share one controller | Each blueprint uses its own `aviatrix_dcf_policy_group` — verify it's not sharing an attachment point |
| `AVXERR-DFW-0025` ruleset not found | Ruleset deleted from controller (drift) | `terraform state rm aviatrix_dcf_ruleset.*` then re-apply |
| EKS nodes `ImagePullBackOff` | docker.io/quay.io blocked by DCF egress | Add registries to `eks_required` or `approved_egress` WebGroup |
| Calico `429 Too Many Requests` | Docker Hub rate limit on anonymous pulls | Create imagePullSecret or push to ECR |
| SmartGroups empty | Cluster not inventoried by controller | Check `aviatrix_kubernetes_cluster` resource, verify `use_csp_credentials = true` and EKS access entry for `aviatrix-role-app` |
| `Unauthorized` in CoPilot K8s | Missing EKS access entry | Add `access_entries` block with `AmazonEKSViewPolicy` for controller IAM role |
| kubectl `Unauthorized` | IAM role not in cluster access entries | `aws eks create-access-entry` + associate `AmazonEKSClusterAdminPolicy` |
| VPC limit exceeded | Default 5 per region | Request increase via AWS Service Quotas |
| SNAT not working | Pod CIDR not excluded from transit advertisements | Add `excluded_advertised_spoke_routes = var.pod_cidr` on transit module |
| `enable_segmentation` conflict | Incompatible with `excluded_advertised_spoke_routes` | Remove `enable_segmentation` |
