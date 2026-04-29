# Multi-Cluster GKE with Aviatrix Transit Architecture

Two GKE clusters on dedicated GCP VPCs, fronted by an Aviatrix transit fabric, demonstrating Distributed Cloud Firewall (DCF) for Kubernetes — the GCP counterpart to `aws-eks-multicluster` and `azure-aks-multicluster`.

> **Aviatrix Controller 9.0+ is required.** The blueprint relies on the controller programming a `0.0.0.0/0` route into each spoke VPC's routing table automatically; pre-9.0 controllers don't.

---

## Prerequisites

### Aviatrix infrastructure

| Component | Requirement | Notes |
|-----------|-------------|-------|
| Aviatrix Controller | 9.0+ | Default-route propagation into the spoke VPC requires controller 9.0. |
| Aviatrix CoPilot | Recommended | Used for DCF visualization and SmartGroup browsing. |
| Aviatrix GCP access account | Onboarded in Controller | Default name in this blueprint: `Google`. The service account JSON loaded into the controller needs at minimum `roles/compute.networkAdmin` (VPC + spoke gateway management) and `roles/container.clusterViewer` (GKE onboarding via `aviatrix_kubernetes_cluster`). |

### Local tools

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.5 | Infrastructure provisioning |
| `gcloud` CLI | latest | GCP authentication and `kubectl` plugin |
| `kubectl` | latest | GKE cluster interaction |
| `gke-gcloud-auth-plugin` | latest | Required by `kubectl` for GKE access tokens (`gcloud components install gke-gcloud-auth-plugin`) |

### GCP authentication

```bash
gcloud auth login
gcloud auth application-default login   # ADC for Terraform google provider
gcloud config set project cmchenry-01
```

### GCP APIs to enable (one-time, project-level)

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  dns.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com
```

### GCP quotas

This blueprint deploys 3 Aviatrix gateways (n1-standard-1) + 2 GKE node pools (e2-standard-2 × ~2 nodes each) + 1 Apache test VM (e2-small). Default project quotas in `us-central1` are usually enough — the typical pinch points:

| Quota | Need | Default |
|-------|------|---------|
| `CPUS` (per region) | ~13 vCPU | 24+ |
| `IN_USE_ADDRESSES` (per region) | ~6 (gateways + ALBs) | 8+ |
| Backend services / URL maps (per project) | 2 each | high |

Check with `gcloud compute project-info describe --project cmchenry-01 --format="json(quotas)"`.

---

## Architecture

```
                        Internet
                           │
            ┌──────────────┴──────────────┐
            ▼                              ▼
   Frontend Gateway              Backend Gateway
   (Global External ALB)         (Global External ALB)
   reserved IP from network/     reserved IP from network/
            │                              │
   ┌────────▼───────────┐         ┌────────▼───────────┐
   │  Frontend VPC       │         │  Backend VPC        │
   │  10.10.0.0/20       │         │  10.20.0.0/20       │
   │                     │         │                     │
   │  GKE frontend       │         │  GKE backend        │
   │  (Dataplane V2 /    │         │  (Dataplane V2 /    │
   │   Cilium eBPF)      │         │   Cilium eBPF)      │
   │  pods 100.64.0.0/16 │         │  pods 100.64.0.0/16 │
   │                     │         │                     │
   │  Aviatrix Spoke GW  │         │  Aviatrix Spoke GW  │
   └─────────┬───────────┘         └─────────┬───────────┘
             │   Aviatrix Transit Fabric     │
             └────────────┬──────────────────┘
                          │
                ┌─────────▼──────────┐
                │ Aviatrix Transit   │
                │ Transit VPC        │
                │ 10.2.0.0/24        │
                └─────────┬──────────┘
                          │
                ┌─────────▼──────────┐
                │ DB VPC 10.5.0.0/22 │
                │ Apache test VM    │
                │ db.gcp.aviatrixdemo.local │
                └────────────────────┘
```

### Why GKE Gateway API instead of an internal NGINX

The AKS variant of this blueprint uses **Azure App Gateway → internal NGINX LB** because Azure's L4 public LB combined with a `0/0 → spoke GW` UDR causes asymmetric routing on response traffic. **GCP doesn't have that trap with Google-managed L7 LBs** — return traffic flows back through Google's LB plane, not the VPC's `0/0` route. So we use **GKE Gateway API** (`gatewayClassName: gke-l7-global-external-managed`) which provisions a native Google global external Application Load Balancer, attaches the Gatus Service via container-native NEGs, and avoids the NGINX hop entirely.

### Pod networking (GKE Dataplane V2)

Both clusters use **GKE Dataplane V2** (Cilium-based eBPF, replaces kube-proxy). Pod IPs come from the alias secondary range `100.64.0.0/16` — **the same in both clusters, overlapping by design**. Aviatrix spoke gateways SNAT pod source IPs to the spoke GW's private IP before transit, so the overlap is invisible east-west. The cluster's `default_snat_status.disabled = true` ensures pod IPs reach the spoke GW unmasqueraded — equivalent to `enableIPv4Masquerade=false` in the AKS variant.

---

## Directory structure

```
gcp-gke-multicluster/
├── network/                # Layer 1: VPCs, transit, spokes, DCF, Cloud DNS
│   ├── main.tf             # Transit + 3 spokes + DB VM + global IPs + DNS zone
│   ├── dcf.tf              # SmartGroups, WebGroups, ruleset
│   ├── dcf-k8s.tf          # K8s-typed SmartGroups (gated by enable_k8s_smartgroup_demo)
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── gke-vpc/        # VPC + node subnet (with pod/service alias ranges)
│       │                   #   + Aviatrix GW subnet + proxy-only subnet + firewall rules
│       └── linux-vm/       # Ubuntu Apache test VM
│
├── clusters/
│   ├── frontend/           # Layer 2: GKE control plane + node pool + GSAs
│   └── backend/            #          (parallel)
│
├── nodes/
│   ├── frontend/           # Layer 3: Helm — ExternalDNS (Cloud DNS) + k8s-firewall
│   └── backend/            #          (parallel)
│
└── k8s-apps/               # Layer 4: Kubernetes manifests (kubectl apply)
    ├── frontend/gatus.yaml     # Gatus + internal-LB Service + Gateway + HTTPRoute
    ├── backend/gatus.yaml
    └── dcf-crd/                # FirewallPolicy / WebGroupPolicy CRD examples
```

---

## Deployment

> Total wall-clock: ~40–55 min when running same-level layers in parallel (network ~10–15m → clusters ~10m parallel → nodes ~3m parallel → kubectl ~3m).

### Step 0 — credentials

```bash
# Aviatrix
source ~/Documents/Scripting/chris-avx-lab/controller_env_ga.sh   # or set AVIATRIX_* manually

# GCP
gcloud auth application-default login
gcloud config set project cmchenry-01
```

### Step 1 — network

```bash
cd network/
cp terraform.tfvars.example terraform.tfvars
# Edit gcp_project_id / aviatrix_gcp_account_name if your defaults differ.
terraform init
terraform apply
```

Creates:
- Aviatrix transit GW + 3 spoke GWs (frontend, backend, db) — all zonal in `us-central1-a`
- 3 GCP VPCs with custom subnets (nodes + Aviatrix GW + proxy-only)
- Cloud DNS private zone bound to all 3 VPCs
- Static A record `db.gcp.aviatrixdemo.local` → DB VM IP
- 2 reserved global external IPv4 addresses for the GKE Gateways
- DCF SmartGroups, WebGroups, ruleset

### Step 2 — GKE clusters (parallel)

```bash
cd ../clusters/frontend && cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply &

cd ../backend && cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply &
wait
```

Each layer creates: GKE cluster (Dataplane V2 / Cilium), primary node pool, node service account, ExternalDNS service account with Workload Identity Federation, and `aviatrix_kubernetes_cluster` registration.

If you set `master_authorized_cidr_blocks` to anything other than `["0.0.0.0/0"]`, also set `aviatrix_controller_public_ip` so the controller's egress IP is appended to the GKE master allowlist for the onboarding handshake.

### Step 3 — Helm add-ons (parallel)

```bash
cd ../../nodes/frontend && terraform init && terraform apply &
cd ../backend && terraform init && terraform apply &
wait
```

Installs ExternalDNS (Cloud DNS provider, Workload Identity) and Aviatrix k8s-firewall.

### Step 4 — Kubernetes apps

Connect kubectl to each cluster, then apply Gatus + Gateway:

```bash
gcloud container clusters get-credentials gke-demo-frontend --zone us-central1-a
kubectl apply -f k8s-apps/frontend/gatus.yaml

gcloud container clusters get-credentials gke-demo-backend --zone us-central1-a
kubectl apply -f k8s-apps/backend/gatus.yaml

# Optional DCF CRD examples (install in either cluster)
kubectl apply -f k8s-apps/dcf-crd/
```

### Verify

```bash
# Reserved Gateway IPs (printed by network/)
terraform -chdir=network output frontend_gateway_global_ip_address
terraform -chdir=network output backend_gateway_global_ip_address

# Open in browser — Gatus UI shows:
#   Internal Services: green (east-west via Aviatrix transit + DCF allow rules)
#   Egress: green for kubernetes.io / npmjs.org / github (DCF WebGroup allow)
#   Threats: blocked (DCF deny rules — geo + ThreatIQ)
```

---

## Destroy

**Order matters** — reverse of deploy:

```bash
# 0. Remove K8s resources first
kubectl delete -f k8s-apps/frontend/gatus.yaml
kubectl delete -f k8s-apps/backend/gatus.yaml
kubectl delete -f k8s-apps/dcf-crd/ --ignore-not-found

# 1. (CRITICAL) flip enable_k8s_smartgroup_demo before destroying clusters
cd network/
terraform apply -var enable_k8s_smartgroup_demo=false

# 2. nodes (parallel)
cd ../nodes/frontend && terraform destroy &
cd ../backend && terraform destroy &
wait

# 3. clusters (parallel)
cd ../../clusters/frontend && terraform destroy &
cd ../backend && terraform destroy &
wait

# 4. network (last)
cd ../../network && terraform destroy
```

---

## GCP-specific gotchas

- **Aviatrix `vpc_id` for GCP** has the form `<vpc_name>~-~<project_id>` — composed locally in `gke-vpc/outputs.tf`. Not the GCP self_link.
- **Aviatrix GW `region`** for GCP is a **zone** (`us-central1-a`), not a region. Aviatrix gateways on GCP are zonal.
- **`single_ip_snat = true` is accepted on GCP** despite the doc claim, but it only covers **internet egress (eth0)**. East-west traffic through the Aviatrix transit is *not* SNATed by `single_ip_snat`. With overlapping pod CIDRs across two GKE clusters (`100.64.0.0/16` in both), un-SNATed pod IPs arriving at the destination spoke route back into the wrong cluster's pod range and replies fail. This blueprint uses `aviatrix_gateway_snat` with `customized_snat` mode and explicit policies for both the transit connection and `eth0` — same pattern as `aws-eks-multicluster`.
- **Default 0/0 propagation** is a controller-9.0 feature. If running 9.0 and the spoke VPC's routing still doesn't have a `0.0.0.0/0` route after `terraform apply`, fall back to a manual `google_compute_route` per VPC pointing at the spoke GW's NIC.
- **GKE master authorized networks** must include the Aviatrix spoke GW egress IP. The clusters layer appends it automatically. When `enable_aviatrix_onboarding=true` and your `master_authorized_cidr_blocks` is restrictive, also set `aviatrix_controller_public_ip` so the controller can reach the master endpoint during onboarding.
