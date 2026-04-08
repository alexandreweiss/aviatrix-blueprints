# Aviatrix Kubernetes Multi-Cloud Blueprints

Terraform blueprints for deploying multi-cluster Kubernetes environments with Aviatrix transit networking and Distributed Cloud Firewall (DCF).

## Patterns

| Pattern | Directory | Description | Isolation Model |
|---------|-----------|-------------|-----------------|
| **A: Cluster-as-a-Service** | [`cluster-aas/`](cluster-aas/) | Dedicated cluster per team | VPC-level (hard boundary) |
| **B: Namespace-as-a-Service** | [`namespace-aas/`](namespace-aas/) | Single shared cluster, namespace per team | Namespace-level (DCF + RBAC) |
| **C: Prod/Non-Prod Hybrid** | [`prod-nonprod-hybrid/`](prod-nonprod-hybrid/) | Separate prod + nonprod clusters with NS-aaS | Two-layer (VPC + namespace) |

Each pattern supports AWS, Azure, and GCP. Standalone CSP-specific blueprints are also available:

| Blueprint | Directory | Description |
|-----------|-----------|-------------|
| Azure AKS Multi-Cluster | [`azure-aks-multicluster/`](azure-aks-multicluster/) | Frontend/backend AKS clusters with FireNet |
| GCP GKE Multi-Cluster | [`gcp-gke-multicluster/`](gcp-gke-multicluster/) | Frontend/backend GKE clusters with Datapath v2 |

## 4-Layer Deployment Model

All patterns follow the same sequential layer structure:

```
Layer 1: Network    →  Transit GW, spoke GWs, VPCs/VNets, SNAT, DNS
Layer 2: Clusters   →  EKS/AKS/GKE control planes, IRSA/Workload Identity
Layer 3: Nodes      →  Node groups, Helm charts (k8s-firewall, ALB/Ingress, ExternalDNS)
Layer 4: CRDs       →  Namespaces, FirewallPolicy, WebGroupPolicy manifests
```

Layers must be deployed in order. Destruction is reverse order.

## Quick Start

### One-Time Setup (GitHub Actions)

```bash
cd .github
python3 setup_gui.py   # Web GUI (opens browser)
# or
./setup.sh             # Interactive CLI
```

Configures S3 state bucket, GitHub secrets/variables, environments, and OIDC. See [WORKFLOW-GUIDE.md](WORKFLOW-GUIDE.md).

### Manual Deploy

Pick a pattern and one or more CSPs. Each `{pattern}/{csp}/` directory is a self-contained stack — deploy them independently or combine across clouds.

```bash
# Example: Pattern C on AWS
cd prod-nonprod-hybrid/aws
cd network   && terraform init && terraform apply -auto-approve && cd ..
cd clusters/prod    && terraform init && terraform apply -auto-approve && cd ../..
cd clusters/nonprod && terraform init && terraform apply -auto-approve && cd ../..
cd nodes/prod       && terraform init && terraform apply -auto-approve && cd ../..
cd nodes/nonprod    && terraform init && terraform apply -auto-approve && cd ../..
kubectl apply -f k8s-apps/dcf-crd/

# Example: Pattern A on Azure + GCP simultaneously
cd cluster-aas/azure/network && terraform init && terraform apply -auto-approve &
cd cluster-aas/gcp/network   && terraform init && terraform apply -auto-approve &
wait
```

You can deploy the same pattern across multiple CSPs (e.g., `cluster-aas/aws` + `cluster-aas/azure` + `cluster-aas/gcp`) or mix patterns per cloud. The Aviatrix transit connects them all.

## Shared Modules

| Module | Path | Description |
|--------|------|-------------|
| Recommendations | [`modules/recommendations/`](modules/) | Optional production-hardening add-ons (Calico, Gatekeeper, Falco, Prometheus, Velero, etc.) |

All recommendation toggles default to `false`. See [`modules/README.md`](modules/README.md) for profiles and usage.

## Documentation

| Document | Description |
|----------|-------------|
| [DEPLOYMENT-WORKFLOW.md](DEPLOYMENT-WORKFLOW.md) | Manual deployment guide for all patterns with verification checklists |
| [WORKFLOW-GUIDE.md](WORKFLOW-GUIDE.md) | GitHub Actions CI/CD setup, usage, state management, and troubleshooting |

## Prerequisites

- Aviatrix Controller with CoPilot
- Aviatrix-onboarded cloud account(s)
- Terraform >= 1.5
- Cloud CLI (aws/az/gcloud) + kubectl >= 1.28
- For CI/CD: GitHub repo with OIDC IAM role

## Repository Structure

```
blueprints/
├── .github/
│   ├── setup.sh              # CLI setup script
│   ├── setup_gui.py          # Web GUI setup
│   └── bootstrap/            # S3 state bucket Terraform
├── cluster-aas/              # Pattern A
│   ├── aws/
│   ├── azure/
│   └── gcp/
├── namespace-aas/            # Pattern B
│   ├── aws/
│   ├── azure/
│   └── gcp/
├── prod-nonprod-hybrid/      # Pattern C (recommended)
│   ├── aws/
│   ├── azure/
│   └── gcp/
├── azure-aks-multicluster/   # Standalone Azure blueprint
├── gcp-gke-multicluster/     # Standalone GCP blueprint
└── modules/
    └── recommendations/      # Optional hardening add-ons
```
