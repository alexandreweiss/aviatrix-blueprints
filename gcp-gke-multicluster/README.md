# GCP GKE Multi-Cluster Blueprint

Multi-cluster GKE deployment with Aviatrix transit networking, VPC-native alias IPs, and DCF-enforced isolation.

## Architecture

```
                    ┌─────────────────┐
                    │  Aviatrix Transit│
                    │  Gateway (Hub)   │
                    │  + FireNet       │
                    └──┬──────┬──────┬┘
                       │      │      │
              ┌────────┘      │      └────────┐
              ▼               ▼               ▼
        ┌───────────┐  ┌───────────┐  ┌───────────┐
        │ Frontend  │  │ Backend   │  │ Database  │
        │ VPC       │  │ VPC       │  │ Spoke     │
        │ + Spoke   │  │ + Spoke   │  │           │
        │ + GKE     │  │ + GKE     │  └───────────┘
        └───────────┘  └───────────┘
```

## Layers

| Layer | Directory | What It Creates |
|-------|-----------|-----------------|
| 1. Network | `network/` | Transit GW (FireNet-enabled), frontend + backend VPCs with spoke GWs, database spoke, Cloud DNS private zone, Cloud Router + NAT, SNAT policies |
| 2. Clusters | `clusters/{name}/` | Private GKE cluster, VPC-native networking (alias IPs), Datapath v2 (Cilium), Workload Identity, Gateway API, Managed Prometheus, Aviatrix onboarding |
| 3. Nodes | `nodes/{name}/` | Node pools (Spot/preemptible, autoscaling, shielded instances), k8s-firewall Helm chart |

## Modules

| Module | Path | Purpose |
|--------|------|---------|
| `gke-cluster` | `modules/gke-cluster/` | GKE control plane, Workload Identity service accounts, Gateway API, Aviatrix cluster registration |
| `gke-node-pool` | `modules/gke-node-pool/` | Node pools with autoscaling, Spot VMs, shielded instances, auto-repair/upgrade |
| `gke-vpc` | `network/modules/gke-vpc/` | VPC subnets with secondary ranges (pods/services), Cloud Router + NAT, firewall rules |

## GCP-Specific Details

- **VPC-Native Networking**: Uses alias IP ranges (secondary ranges on subnets) instead of ENIConfig. Pods get IPs from `100.64.0.0/16`.
- **Datapath v2 (Cilium)**: Advanced network policy and observability built into GKE. Replaces kube-proxy with eBPF.
- **Private Clusters**: Nodes have no public IPs. Cloud Router + NAT provides fallback egress for private nodes.
- **Workload Identity**: Pods authenticate as GCP service accounts via federation. Pre-configured for ExternalDNS and Gateway API controller.
- **Gateway API**: Modern ingress replacement (GCP equivalent of AWS ALB Controller). Uses GKE Gateway classes.
- **Managed Prometheus**: Built-in monitoring enabled at the cluster level.
- **Shielded Instances**: Nodes deploy with secure boot enabled.
- **No CoreDNS patch needed**: GKE natively handles Cloud DNS resolution.

## Deploy

```bash
cd gcp-gke-multicluster

# Layer 1
cd network && terraform init && terraform apply -auto-approve && cd ..

# Layer 2
cd clusters/frontend && terraform init && terraform apply -auto-approve && cd ../..

# Layer 3
cd nodes/frontend && terraform init && terraform apply -auto-approve && cd ../..
```

## Variables

### Network Layer

| Variable | Default | Description |
|----------|---------|-------------|
| `transit_cidr` | — | Transit VPC CIDR |
| `frontend_cidr` | — | Frontend VPC CIDR |
| `backend_cidr` | — | Backend VPC CIDR |
| `db_cidr` | — | Database spoke CIDR |
| `pod_cidr` | `100.64.0.0/16` | Pod overlay CIDR (secondary range) |

## Prerequisites

- Aviatrix Controller with CoPilot
- Aviatrix-onboarded GCP account
- Terraform >= 1.5, gcloud CLI, kubectl >= 1.28

See [DEPLOYMENT-WORKFLOW.md](../DEPLOYMENT-WORKFLOW.md) for full details.
