# Pattern B: Namespace-as-a-Service

Single shared Kubernetes cluster with namespace-level isolation enforced by Aviatrix DCF and Kubernetes RBAC.

## Architecture

```
                    ┌─────────────────┐
                    │  Aviatrix Transit│
                    │    Gateway (Hub) │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │   Shared VPC    │
                    │   + Spoke GW    │
                    │                 │
                    │ ┌─────────────┐ │
                    │ │ Shared EKS  │ │
                    │ │             │ │
                    │ │ ┌─────────┐ │ │
                    │ │ │ team-a  │ │ │
                    │ │ ├─────────┤ │ │
                    │ │ │ team-b  │ │ │
                    │ │ ├─────────┤ │ │
                    │ │ │ team-c  │ │ │
                    │ │ └─────────┘ │ │
                    │ └─────────────┘ │
                    └─────────────────┘
```

All teams share one cluster. Isolation is provided by DCF SmartGroups (keyed on `k8s_namespace`) and RBAC RoleBindings that scope teams to their namespace.

## Supported CSPs

| Directory | Cloud | Clusters | Region Default |
|-----------|-------|----------|----------------|
| `aws/` | AWS (EKS) | shared | us-east-1 |
| `azure/` | Azure (AKS) | shared | — |
| `gcp/` | GCP (GKE) | shared | — |

## Layers

| Layer | Directory | What It Creates | ~Time |
|-------|-----------|-----------------|-------|
| 1. Network | `{csp}/network/` | Transit GW, shared VPC + spoke GW, Route53/DNS zone, SNAT policies | 5-8 min |
| 2. Cluster | `{csp}/clusters/shared/` | EKS/AKS/GKE control plane, VPC CNI custom networking, Aviatrix cluster onboarding | 10-15 min |
| 3. Nodes | `{csp}/nodes/shared/` | Shared node group (m5.xlarge, SPOT), ENIConfig, k8s-firewall Helm chart | 5-8 min |
| 4. CRDs | `{csp}/k8s-apps/dcf-crd/` | Namespaces, RBAC, FirewallPolicy CRDs, WebGroupPolicy CRDs | < 1 min |

## Key Design Decisions

- **Single cluster, multi-tenant**: Lower cost and operational overhead vs. Pattern A. Trade-off: blast radius is larger.
- **DCF as primary isolation**: SmartGroups match on `k8s_namespace` label. DCF sees post-SNAT traffic, so VPC SmartGroups match source IPs (spoke gateway).
- **RBAC is NOT a network boundary**: Kubernetes RBAC prevents accidental cross-namespace access but does not enforce network isolation. DCF provides the hard boundary.
- **Team self-service CRDs**: Teams can author FirewallPolicy CRDs (priority 70-99) to control their own egress destinations via WebGroups.

## Layer 4: CRD Details

### Namespaces Created

| Namespace | Purpose | Labels |
|-----------|---------|--------|
| `team-a` | Team A workloads | `team: team-a` |
| `team-b` | Team B workloads | `team: team-b` |
| `team-c` | Team C workloads | `team: team-c` |
| `monitoring` | Shared observability | — |
| `istio-system` | Service mesh | — |
| `cert-manager` | TLS automation | — |

### FirewallPolicy CRDs

- **team-a**: Allows `app=api` pods to reach `api.stripe.com`, `api.sendgrid.com` on TCP 443
- **team-b**: Allows `app=frontend` to CDN domains (CloudFront, Cloudflare, Akamai) and `app=analytics` to Segment/Mixpanel on TCP 443

## Deploy (AWS Example)

```bash
cd namespace-aas/aws

# Layer 1
cd network && terraform init && terraform apply -auto-approve && cd ..

# Layer 2
cd clusters/shared && terraform init && terraform apply -auto-approve && cd ../..

# Layer 3
cd nodes/shared && terraform init && terraform apply -auto-approve && cd ../..

# Layer 4
aws eks update-kubeconfig --name naas-shared-eks --region us-east-1
kubectl apply -f k8s-apps/dcf-crd/namespace-setup.yaml
kubectl apply -f k8s-apps/dcf-crd/firewallpolicy-team-a.yaml
kubectl apply -f k8s-apps/dcf-crd/firewallpolicy-team-b.yaml
```

## Destroy (Reverse Order)

```bash
cd namespace-aas/aws

kubectl delete -f k8s-apps/dcf-crd/ --ignore-not-found
cd nodes/shared && terraform destroy -auto-approve && cd ../..
cd clusters/shared && terraform destroy -auto-approve && cd ../..
cd network && terraform destroy -auto-approve && cd ..
```

## Variables

### Network Layer

| Variable | Default | Description |
|----------|---------|-------------|
| `name_prefix` | `naas` | Resource naming prefix |
| `aviatrix_aws_account_name` | — | Aviatrix-onboarded AWS account name (required) |
| `aws_region` | `us-east-1` | Target region |
| `shared_vpc_cidr` | `10.10.0.0/16` | Shared VPC CIDR |
| `transit_cidr` | `10.2.0.0/20` | Transit VPC CIDR |
| `pod_cidr` | `100.64.0.0/16` | Pod overlay CIDR |
| `team_namespaces` | `[team-a, team-b, team-c]` | Namespace list for DCF SmartGroups |

### Cluster Layer

| Variable | Default | Description |
|----------|---------|-------------|
| `kubernetes_version` | `1.31` | EKS Kubernetes version |
| `enable_private_endpoint` | `false` | Private-only API server |
| `enable_control_plane_logging` | `false` | Control plane audit logging |

### Nodes Layer

| Variable | Default | Description |
|----------|---------|-------------|
| `node_group_config.desired_size` | `3` | Desired node count |
| `node_group_config.instance_type` | `m5.xlarge` | EC2 instance type |
| `node_group_config.capacity_type` | `SPOT` | SPOT or ON_DEMAND |

## Prerequisites

- Aviatrix Controller with CoPilot
- Aviatrix-onboarded cloud account
- Terraform >= 1.5, AWS CLI >= 2.61, kubectl >= 1.28
- Sufficient quotas (3 VPCs, 4 EIPs per region)

See [DEPLOYMENT-WORKFLOW.md](../DEPLOYMENT-WORKFLOW.md) for full details.
