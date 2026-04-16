# Pattern C: Prod/Non-Prod Hybrid (Recommended)

Separate production and non-production clusters with two-layer DCF isolation: environment-level (VPC) and namespace-level (CRDs). Combines the strong isolation of Pattern A with the team self-service of Pattern B.

## Architecture

```
                    ┌─────────────────┐
                    │  Aviatrix Transit│
                    │    Gateway (Hub) │
                    │       (HA)       │
                    └──┬──────┬──────┬┘
                       │      │      │
              ┌────────┘      │      └────────┐
              ▼               ▼               ▼
        ┌───────────┐  ┌───────────┐  ┌───────────┐
        │Production │  │Non-Prod   │  │ Database  │
        │  VPC      │  │  VPC      │  │  Spoke    │
        │  + Spoke  │  │  + Spoke  │  │(prod-only)│
        │           │  │           │  └───────────┘
        │ ┌───────┐ │  │ ┌───────┐ │
        │ │pc2-   │ │  │ │pc2-   │ │
        │ │prod   │ │  │ │nonprod│ │
        │ │       │ │  │ │       │ │
        │ │team-a │ │  │ │team-a │ │
        │ │team-b │ │  │ │team-b │ │
        │ └───────┘ │  │ │sandbox│ │
        └───────────┘  │ └───────┘ │
                       └───────────┘
```

Production and non-production are hard-isolated at the VPC/spoke level. Within each cluster, teams get their own namespaces with DCF-enforced egress policies. The database spoke is only reachable from production.

## Supported CSPs

| Directory | Cloud | Clusters | Region Default |
|-----------|-------|----------|----------------|
| `aws/` | AWS (EKS) | prod, nonprod | us-east-2 |
| `azure/` | Azure (AKS) | prod, nonprod | — |
| `gcp/` | GCP (GKE) | prod, nonprod | — |

## Layers

| Layer | Directory | What It Creates | ~Time |
|-------|-----------|-----------------|-------|
| 1. Network | `{csp}/network/` | Transit GW (HA), prod VPC + spoke, nonprod VPC + spoke, database spoke, Route53/DNS zone, SNAT policies | 5-8 min |
| 2. Clusters | `{csp}/clusters/{env}/` | EKS/AKS/GKE control plane per environment, VPC CNI, managed node groups, Aviatrix cluster onboarding | 10-15 min each |
| 3. Nodes | `{csp}/nodes/{env}/` | k8s-firewall Helm chart (DCF CRD engine) | 5-8 min each |
| 4. CRDs | `{csp}/k8s-apps/dcf-crd/` | Namespaces, FirewallPolicy CRDs (strict for prod, relaxed for nonprod) | < 1 min |

## Key Design Decisions

- **Two-layer isolation**: VPC boundaries block prod/nonprod cross-traffic at Layer 1. DCF CRDs enforce per-team egress at Layer 4.
- **Database spoke is prod-only**: Transit routing ensures nonprod cannot reach the database spoke, regardless of DCF rules.
- **Stricter prod policies**: Production FirewallPolicies allow only pre-approved API endpoints. Nonprod policies are more relaxed; sandbox allows all HTTPS egress.
- **HA by default**: Transit and spoke gateways deploy with HA enabled (`enable_ha = true`).

## Layer 4: CRD Details

### Production Namespaces

| Namespace | Egress Policy |
|-----------|--------------|
| `team-a-prod` | TCP 443 to Stripe, Datadog, AWS APIs only |
| `team-b-prod` | TCP 443 to CloudFront, Akamai only |
| `monitoring` | Observability stack |

### Non-Production Namespaces

| Namespace | Egress Policy |
|-----------|--------------|
| `team-a-dev` | TCP 443 to npm, GitHub, AWS APIs, Stripe |
| `team-b-staging` | TCP 443 to staging CDN and build tools |
| `sandbox` | TCP 80/443 to any destination (relaxed) |
| `monitoring` | Observability stack |

## Deploy (AWS Example)

```bash
cd prod-nonprod-hybrid/aws

# Layer 1
cd network && terraform init && terraform apply -auto-approve && cd ..

# Layer 2 (parallel)
cd clusters/prod && terraform init && terraform apply -auto-approve &
cd clusters/nonprod && terraform init && terraform apply -auto-approve &
wait

# Layer 3 (parallel)
cd nodes/prod && terraform init && terraform apply -auto-approve &
cd nodes/nonprod && terraform init && terraform apply -auto-approve &
wait

# Layer 4
aws eks update-kubeconfig --name pc2-prod --region us-east-2
kubectl apply -f k8s-apps/dcf-crd/prod-namespaces.yaml
kubectl apply -f k8s-apps/dcf-crd/firewallpolicy-prod.yaml

aws eks update-kubeconfig --name pc2-nonprod --region us-east-2
kubectl apply -f k8s-apps/dcf-crd/nonprod-namespaces.yaml
kubectl apply -f k8s-apps/dcf-crd/firewallpolicy-nonprod.yaml
```

## Destroy (Reverse Order)

```bash
cd prod-nonprod-hybrid/aws

for env in prod nonprod; do
  (cd nodes/$env && terraform destroy -auto-approve) &
done
wait

for env in prod nonprod; do
  (cd clusters/$env && terraform destroy -auto-approve) &
done
wait

cd network && terraform destroy -auto-approve && cd ..
```

## Variables

### Network Layer

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_account_name` | — | Aviatrix-onboarded AWS account name (required) |
| `aws_region` | `us-east-2` | Target region |
| `transit_cidr` | `10.2.0.0/20` | Transit VPC CIDR |
| `prod_vpc_cidr` | `10.10.0.0/20` | Production VPC CIDR |
| `nonprod_vpc_cidr` | `10.20.0.0/20` | Non-production VPC CIDR |
| `db_vpc_cidr` | `10.5.0.0/22` | Database spoke CIDR |
| `pod_cidr` | `100.64.0.0/16` | Shared pod overlay CIDR |
| `enable_ha` | `true` | HA for transit and spoke gateways |
| `teams` | map | Team namespace definitions |

### Cluster Layer

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_version` | `1.31` | EKS Kubernetes version |
| `enable_private_endpoint` | `false` | Private-only API server |
| `enable_control_plane_logging` | `false` | Control plane audit logging |

### Nodes Layer

| Variable | Default | Description |
|----------|---------|-------------|
| Prod: `desired_size` | `2` | Prod node count |
| Nonprod: `desired_size` | `2` | Nonprod node count |
| `instance_type` | `t3.large` | EC2 instance type |

## Verification

```bash
# Prod cluster
aws eks update-kubeconfig --name pc2-prod --region us-east-2
kubectl get nodes
kubectl get firewallpolicies -A

# Nonprod cluster
aws eks update-kubeconfig --name pc2-nonprod --region us-east-2
kubectl get nodes
kubectl get firewallpolicies -A

# Verify in CoPilot:
#   Security > DCF — two-layer rules (env + namespace)
#   nonprod → prod traffic: DENIED
#   nonprod → database spoke: DENIED
```

## Prerequisites

- Aviatrix Controller with CoPilot
- Aviatrix-onboarded cloud account
- Terraform >= 1.5, AWS CLI >= 2.61, kubectl >= 1.28
- Sufficient quotas (5 VPCs, 10 EIPs per region)

See [DEPLOYMENT-WORKFLOW.md](../DEPLOYMENT-WORKFLOW.md) for full details.
