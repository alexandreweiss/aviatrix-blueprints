# Aviatrix Kubernetes Multi-Cloud Blueprints

Production-ready Terraform blueprints for deploying Kubernetes environments with Aviatrix transit networking and Distributed Cloud Firewall (DCF).

## Kubernetes Patterns

Three patterns for different isolation requirements. Each supports AWS, Azure, and GCP.

| Pattern | Directory | Isolation | Clusters | Best For |
|---|---|---|---|---|
| **k8s-cluster-aas** | [`blueprints/k8s-cluster-aas/`](blueprints/k8s-cluster-aas/) | VPC-level (hard boundary) | 1 per team | Strict isolation, compliance |
| **k8s-namespace-aas** | [`blueprints/k8s-namespace-aas/`](blueprints/k8s-namespace-aas/) | Namespace (DCF + Calico) | 1 shared | Cost-conscious, trusted teams |
| **k8s-prod-nonprod-hybrid** ⭐ | [`blueprints/k8s-prod-nonprod-hybrid/`](blueprints/k8s-prod-nonprod-hybrid/) | VPC + namespace (two-layer) | 2 (prod/nonprod) | Most organizations |

## Standalone Blueprints

| Blueprint | Directory | Description | Cloud |
|---|---|---|---|
| aws-eks-multicluster | [`blueprints/aws-eks-multicluster/`](blueprints/aws-eks-multicluster/) | DCF with EKS frontend/backend | AWS |
| azure-aks-multicluster | [`azure-aks-multicluster/`](azure-aks-multicluster/) | AKS clusters with FireNet | Azure |
| gcp-gke-multicluster | [`gcp-gke-multicluster/`](gcp-gke-multicluster/) | GKE clusters with Datapath v2 | GCP |
| prevent-lateral-movement-vm-tags | [`blueprints/prevent-lateral-movement-vm-tags/`](blueprints/prevent-lateral-movement-vm-tags/) | Zero Trust DCF with VM tags | AWS |
| zero-trust-segmentation | [`blueprints/zero-trust-segmentation/`](blueprints/zero-trust-segmentation/) | DCF with SmartGroups | AWS |

## 4-Layer Deployment Model

All K8s patterns follow the same structure:

```
Layer 1: network/          ← Transit GW, Spoke GWs, VPCs, SNAT, DNS, DCF rules
Layer 2: clusters/         ← EKS/AKS/GKE control planes, IRSA, access entries
Layer 3: nodes/            ← Node groups, Calico, k8s-firewall, ALB, ExternalDNS
Layer 4: k8s-apps/         ← Namespaces, FirewallPolicy, NetworkPolicy CRDs
```

Layers must be deployed in order. Layers at the same level (e.g., multiple clusters) can run in parallel.

## Quick Start

### Prerequisites

- Aviatrix Controller with CoPilot
- Cloud account onboarded in Aviatrix
- Terraform ≥ 1.5, AWS/Azure/GCP CLI, kubectl ≥ 1.28

### Deploy (example: k8s-cluster-aas on AWS)

```bash
cd blueprints/k8s-cluster-aas/aws

# Layer 1: Network
cd network && terraform init && terraform apply -var="aviatrix_aws_account_name=<account>" && cd ..

# Layer 2: Clusters (parallel)
for team in team-a team-b team-c; do
  terraform -chdir=clusters/$team init
  terraform -chdir=clusters/$team apply -var="aviatrix_aws_account_name=<account>" -auto-approve &
done && wait

# Layer 3: Nodes (parallel)
for team in team-a team-b team-c; do
  terraform -chdir=nodes/$team init
  terraform -chdir=nodes/$team apply -auto-approve &
done && wait
```

See [DEPLOYMENT-WORKFLOW.md](DEPLOYMENT-WORKFLOW.md) for complete instructions, all patterns, and verification checklists.

## Optional Hardening

All patterns include opt-in toggles (all default `false`) via the shared recommendations module:

```hcl
# nodes/*/terraform.tfvars
enable_network_policy           = true  # Calico NetworkPolicy
enable_gatekeeper               = true  # OPA Gatekeeper admission control
enable_external_secrets         = true  # AWS Secrets Manager sync
enable_falco                    = true  # Runtime threat detection
enable_prometheus_stack         = true  # Prometheus + Grafana
enable_fluent_bit               = true  # CloudWatch log aggregation
enable_node_termination_handler = true  # Required for SPOT instances
enable_cluster_autoscaler       = true  # Dynamic scaling
enable_velero                   = true  # Backup to S3
```

See [`modules/recommendations/`](modules/recommendations/) for full details.

## Repository Structure

```
blueprints/
├── blueprints/
│   ├── k8s-cluster-aas/          # Pattern A: dedicated cluster per team
│   │   ├── aws/ azure/ gcp/
│   │   └── README.md
│   ├── k8s-namespace-aas/        # Pattern B: shared cluster
│   │   ├── aws/ azure/ gcp/
│   │   └── README.md
│   ├── k8s-prod-nonprod-hybrid/  # Pattern C: prod/nonprod (recommended)
│   │   ├── aws/ azure/ gcp/
│   │   └── README.md
│   ├── aws-eks-multicluster/
│   ├── zero-trust-segmentation/
│   └── prevent-lateral-movement-vm-tags/
├── azure-aks-multicluster/
├── gcp-gke-multicluster/
├── modules/
│   └── recommendations/          # Optional hardening add-ons
└── docs/
```

## Documentation

| Document | Description |
|---|---|
| [DEPLOYMENT-WORKFLOW.md](DEPLOYMENT-WORKFLOW.md) | Step-by-step deployment guide, verification checklists, troubleshooting |
| [WORKFLOW-GUIDE.md](WORKFLOW-GUIDE.md) | GitHub Actions CI/CD setup and state management |
