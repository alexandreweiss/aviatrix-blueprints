# Azure AKS Multi-Cluster Blueprint

Multi-cluster AKS deployment with Aviatrix transit networking, Azure CNI overlay, and DCF-enforced isolation.

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
        │ VNet      │  │ VNet      │  │ Spoke     │
        │ + Spoke   │  │ + Spoke   │  │           │
        │ + AKS     │  │ + AKS     │  └───────────┘
        └───────────┘  └───────────┘
```

## Layers

| Layer | Directory | What It Creates |
|-------|-----------|-----------------|
| 1. Network | `network/` | Transit GW (FireNet-enabled), frontend + backend VNets with spoke GWs, database spoke, Azure Private DNS zone, SNAT policies |
| 2. Clusters | `clusters/{name}/` | Private AKS cluster, Azure CNI overlay (100.64.0.0/16 pods), Workload Identity + OIDC, Aviatrix onboarding |
| 3. Nodes | `nodes/{name}/` | User node pools (Spot VMs, autoscaling), k8s-firewall Helm chart, CoreDNS patch for Azure Private DNS |

## Modules

| Module | Path | Purpose |
|--------|------|---------|
| `aks-cluster` | `modules/aks-cluster/` | AKS control plane, system node pool, Workload Identity federation, Aviatrix cluster registration |
| `aks-node-group` | `modules/aks-node-group/` | User node pools with autoscaling, Spot VM support, labels and taints |
| `aks-vnet` | `network/modules/aks-vnet/` | VNet subnets (GW, system, user), NSGs, route tables |

## Azure-Specific Details

- **Azure CNI Overlay**: Pods get IPs from `100.64.0.0/16` (non-routable, overlapping across clusters). No ENIConfig needed — Azure handles this natively.
- **Private Clusters**: AKS API server accessible via private endpoint only.
- **Workload Identity**: Pod authentication using Azure AD federated credentials (equivalent to AWS IRSA). Pre-configured for ExternalDNS and NGINX Ingress Controller.
- **CoreDNS Patch**: Nodes layer patches CoreDNS to forward Azure Private DNS zone queries to `168.63.129.16`.
- **FireNet**: Transit gateway deploys with FireNet enabled for optional NGFW integration.

## Deploy

```bash
cd azure-aks-multicluster

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
| `transit_cidr` | `10.32.0.0/20` | Transit VNet CIDR |
| `frontend_cidr` | `10.30.0.0/20` | Frontend VNet CIDR |
| `backend_cidr` | `10.31.0.0/20` | Backend VNet CIDR |
| `db_cidr` | `10.35.0.0/22` | Database spoke CIDR |
| `pod_cidr` | `100.64.0.0/16` | Pod overlay CIDR |

## Prerequisites

- Aviatrix Controller with CoPilot
- Aviatrix-onboarded Azure account
- Terraform >= 1.5, Azure CLI, kubectl >= 1.28

See [DEPLOYMENT-WORKFLOW.md](../DEPLOYMENT-WORKFLOW.md) for full details.
