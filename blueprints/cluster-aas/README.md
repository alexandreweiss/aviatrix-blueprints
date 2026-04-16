# Pattern A: Cluster-as-a-Service

Dedicated EKS/AKS/GKE cluster per team with VPC-level isolation enforced by Aviatrix Distributed Cloud Firewall (DCF).

## Architecture

```
                    ┌─────────────────┐
                    │  Aviatrix Transit│
                    │    Gateway (Hub) │
                    └──┬──────┬──────┬┘
                       │      │      │
              ┌────────┘      │      └────────┐
              ▼               ▼               ▼
        ┌───────────┐  ┌───────────┐  ┌───────────┐
        │  Team-A   │  │  Team-B   │  │  Team-C   │
        │  VPC/VNet │  │  VPC/VNet │  │  VPC/VNet │
        │  + Spoke  │  │  + Spoke  │  │  + Spoke  │
        │  + EKS    │  │  + EKS    │  │  + EKS    │
        └───────────┘  └───────────┘  └───────────┘
                               │
                        ┌──────┴──────┐
                        │ Database    │
                        │ Spoke VPC   │
                        └─────────────┘
```

Each team gets its own VPC, spoke gateway, and Kubernetes cluster. Inter-team traffic is routed through the Aviatrix transit and subject to DCF rules.

## Supported CSPs

| Directory | Cloud | Clusters | Region Default |
|-----------|-------|----------|----------------|
| `aws/` | AWS (EKS) | team-a, team-b, team-c | us-west-2 |
| `azure/` | Azure (AKS) | team-a, team-b, team-c | — |
| `gcp/` | GCP (GKE) | team-a, team-b, team-c | — |

## Layers

Layers must be deployed in order. Each layer reads outputs from the previous via `terraform_remote_state`.

| Layer | Directory | What It Creates | ~Time |
|-------|-----------|-----------------|-------|
| 1. Network | `{csp}/network/` | Transit GW, 3 team VPCs + spoke GWs, database spoke, Route53/DNS zone, SNAT policies | 5-8 min |
| 2. Clusters | `{csp}/clusters/{team}/` | EKS/AKS/GKE control plane, VPC CNI config, IRSA/Workload Identity roles, Aviatrix cluster onboarding | 10-15 min each |
| 3. Nodes | `{csp}/nodes/{team}/` | Managed node group, ENIConfig (AWS), k8s-firewall Helm chart, ALB Controller, ExternalDNS | 5-8 min each |

No Layer 4 (CRDs) — teams own their clusters and manage their own workloads.

## Key Design Decisions

- **Pod CIDR overlay**: All clusters share `100.64.0.0/16` (RFC 6598). Non-routable; Aviatrix SNAT translates pod traffic to spoke gateway IPs before transit.
- **Isolation model**: VPC boundaries provide primary isolation. DCF SmartGroups use VPC membership for policy matching.
- **SNAT policies**: 3 rules per spoke — pod-to-transit (east-west), pod-to-internet (egress), node-to-internet (node egress).
- **Team admin**: Each team gets cluster-admin on their own cluster only.

## Deploy (AWS Example)

```bash
cd cluster-aas/aws

# Layer 1
cd network && terraform init && terraform apply -auto-approve && cd ..

# Layer 2 (parallel)
for team in team-a team-b team-c; do
  (cd clusters/$team && terraform init && terraform apply -auto-approve) &
done
wait

# Layer 3 (parallel)
for team in team-a team-b team-c; do
  (cd nodes/$team && terraform init && terraform apply -auto-approve) &
done
wait
```

## Destroy (Reverse Order)

```bash
cd cluster-aas/aws

for team in team-a team-b team-c; do
  (cd nodes/$team && terraform destroy -auto-approve) &
done
wait

for team in team-a team-b team-c; do
  (cd clusters/$team && terraform destroy -auto-approve) &
done
wait

cd network && terraform destroy -auto-approve && cd ..
```

## Variables

### Network Layer

| Variable | Default | Description |
|----------|---------|-------------|
| `name_prefix` | `caas` | Resource naming prefix |
| `aviatrix_aws_account_name` | — | Aviatrix-onboarded AWS account name (required) |
| `aws_region` | `us-west-2` | Target region |
| `transit_cidr` | `10.2.0.0/20` | Transit VPC CIDR |
| `team_a_vpc_cidr` | `10.10.0.0/20` | Team A VPC CIDR |
| `team_b_vpc_cidr` | `10.11.0.0/20` | Team B VPC CIDR |
| `team_c_vpc_cidr` | `10.12.0.0/20` | Team C VPC CIDR |
| `db_vpc_cidr` | `10.5.0.0/22` | Database spoke CIDR |
| `pod_cidr` | `100.64.0.0/16` | Shared pod overlay CIDR |

### Cluster Layer

| Variable | Default | Description |
|----------|---------|-------------|
| `kubernetes_version` | `1.31` | EKS Kubernetes version |
| `enable_private_endpoint` | `false` | Private-only API server (requires VPN/bastion) |
| `enable_control_plane_logging` | `false` | Audit, API, authenticator logs to CloudWatch |

### Nodes Layer

| Variable | Default | Description |
|----------|---------|-------------|
| `node_group_config.min_size` | `1` | Minimum nodes |
| `node_group_config.max_size` | `3` | Maximum nodes |
| `node_group_config.desired_size` | `2` | Desired node count |
| `node_group_config.instance_type` | `t3.large` | EC2 instance type |
| `node_group_config.capacity_type` | `SPOT` | SPOT or ON_DEMAND |

## Prerequisites

- Aviatrix Controller with CoPilot
- Aviatrix-onboarded cloud account
- Terraform >= 1.5, AWS CLI >= 2.61, kubectl >= 1.28
- Sufficient VPC/EIP quotas (6 VPCs, 12 EIPs per region)

See [DEPLOYMENT-WORKFLOW.md](../DEPLOYMENT-WORKFLOW.md) for full details.
