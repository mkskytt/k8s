# Kubernetes GitOps Cluster

This repository contains a complete Kubernetes cluster configuration managed through GitOps using Flux CD. The setup includes automated application deployment, secret management, DNS management, and monitoring capabilities.

This repository is designed to be used as a template for setting up your own GitOps-managed Kubernetes cluster. You can either apply this configuration to an existing cluster or create a new cluster using the provided instructions.

## Overview

This cluster configuration provides:
- **GitOps deployment** via Flux CD
- **Secret encryption** using SOPS with Age
- **DNS management** with external-dns and Cloudflare
- **Secure ingress** through Cloudflare tunnels
- **Monitoring** with Grafana Alloy
- **Policy management** with Kyverno
- **Demo applications** for testing

## Prerequisites

Before setting up the cluster, ensure you have the following tools installed:

### Required Tools
- **kubectl** - Kubernetes command-line tool
- **flux** - Flux CD CLI ([installation guide](https://fluxcd.io/flux/installation/))
- **age** - Encryption tool for secrets ([installation guide](https://github.com/FiloSottile/age))
- **sops** - Secrets OPerationS ([installation guide](https://github.com/mozilla/sops))
- **git** - Version control
- **kind** - Kubernetes in Docker (only if creating a new cluster) ([installation guide](https://kind.sigs.k8s.io/docs/user/quick-start/#installation))

### Kubernetes Cluster
You need a running Kubernetes cluster. This can be:
- A managed cluster (EKS, GKE, AKS, etc.)
- A local development cluster (kind, minikube, etc.)
- A self-managed cluster (k3s, etc.)

**Recommended for development**: Use `kind` (Kubernetes in Docker) for local testing and development.

### External Dependencies
- **Cloudflare account** with API access for DNS management
- **GitHub repository access** for this configuration

## Getting Started

This repository can be used with either an existing Kubernetes cluster or a new cluster created specifically for this configuration.

### Option 1: Using an Existing Cluster

If you already have a Kubernetes cluster available:

1. Ensure you have `kubectl` configured to access your cluster
2. Verify cluster access: `kubectl cluster-info`
3. Continue to the [Secret Management](#1-set-up-secret-management) section below

### Option 2: Creating a New Cluster with kind

If you need to create a new cluster for development or testing:

```bash
# Create a new kind cluster
kind create cluster --name gitops-cluster

# Verify the cluster is running
kubectl cluster-info --context kind-gitops-cluster

# Set the current context (if not already set)
kubectl config use-context kind-gitops-cluster
```

**Optional**: Create a multi-node cluster for testing:
```bash
# Create a kind configuration file
cat << EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

# Create cluster with the configuration
kind create cluster --name gitops-cluster --config kind-config.yaml
```

## Cluster Bootstrap Instructions

Once you have a Kubernetes cluster available (either existing or newly created), follow these steps to bootstrap GitOps management:

### 1. Set Up Secret Management

Generate an Age key for secret encryption:

```bash
# Generate a new Age key
age-keygen -o age.agekey

# Get the public key (needed for .sops.yaml)
age-keygen -y age.agekey
```

Create the SOPS Age secret in the cluster:

```bash
# Create the flux-system namespace
kubectl create namespace flux-system

# Create the Age secret for SOPS
kubectl create secret generic sops-age \
    --namespace=flux-system \
    --from-file=age.agekey=age.agekey
```

### 2. Bootstrap Flux CD

Install and configure Flux CD to manage this repository:

```bash
# Check prerequisites
flux check --pre

# Bootstrap Flux CD with your repository
# Replace <your-github-username> and <your-repository-name> with your values
flux bootstrap github \
    --owner=<your-github-username> \
    --repository=<your-repository-name> \
    --branch=main \
    --path=./cluster \
    --personal
```

When prompted, provide your GitHub personal access token with repository access.

**Note**: If you're using this repository as a template, make sure to update the owner and repository name to match your forked repository.

### 3. Verify the Setup

Check that Flux is running and syncing:

```bash
# Check Flux components
flux get kustomizations

# Check GitRepository source
flux get sources git

# Watch for reconciliation
flux logs --follow
```

## Flux CD Overview

### How Flux CD Operates

Flux CD implements GitOps by:

1. **Monitoring**: Continuously watches this Git repository for changes
2. **Synchronizing**: Automatically applies Kubernetes manifests when changes are detected
3. **Reconciling**: Ensures the cluster state matches the desired state in Git
4. **Alerting**: Provides status updates and notifications about deployments

### Repository Structure

```
cluster/
├── flux-system/          # Flux CD system components
│   ├── gotk-components.yaml
│   ├── gotk-sync.yaml
│   └── kustomization.yaml
├── apps/                 # Application deployments
│   ├── cloudflare-tunnel/
│   ├── external-dns/
│   ├── demo-app/
│   ├── grafana-alloy/
│   ├── keda/
│   └── kyverno/
└── apps.yaml            # Apps kustomization
```

### GitOps Workflow

1. **Make changes** to YAML files in this repository
2. **Commit and push** changes to the main branch
3. **Flux detects** changes within ~1 minute
4. **Applications are deployed** automatically
5. **Monitor status** using `flux get kustomizations`

## Secret Management

### SOPS and Age Encryption

Sensitive data is encrypted using SOPS with Age encryption:

- **Age key**: Generated during setup, stored as a Kubernetes secret
- **SOPS configuration**: Defined in `.sops.yaml`
- **Encrypted files**: Named with `.sops.yaml` suffix

### Working with Secrets

Encrypt a new secret file:
```bash
# Create a secret file
kubectl create secret generic my-secret \
    --from-literal=key=value \
    --dry-run=client -o yaml > secret.yaml

# Encrypt with SOPS
sops --encrypt --in-place secret.yaml

# Rename to indicate it's encrypted
mv secret.yaml secret.sops.yaml
```

Edit an encrypted secret:
```bash
sops secret.sops.yaml
```

## Applications

### Included Applications

1. **External DNS**
   - Automatically manages DNS records in Cloudflare
   - Syncs Ingress and Service resources with DNS

2. **Cloudflare Tunnel**
   - Provides secure ingress to cluster services
   - Eliminates need for public load balancers

3. **Grafana Alloy**
   - Telemetry collector for observability
   - Forwards metrics and logs to Grafana Cloud

4. **Demo App**
   - Simple nginx application for testing
   - Demonstrates ingress and DNS integration

5. **KEDA (Kubernetes Event-Driven Autoscaling)**
   - Enables event-driven autoscaling for workloads
   - Scales based on external metrics, queues, and custom triggers
   - Integrates with 60+ external systems for scaling decisions

6. **Kyverno (Policy Engine)**
   - Kubernetes-native policy management for validation, mutation, and generation
   - Declarative policies using YAML (no complex policy language required)
   - Admission control, background processing, and compliance reporting
   - Supports Pod Security Standards, resource validation, and configuration generation

### Adding New Applications

1. Create a new directory under `cluster/apps/`
2. Add Kubernetes manifests or Helm releases
3. Create a `kustomization.yaml` file
4. Commit and push changes

Example structure:
```
cluster/apps/my-app/
├── namespace.yaml
├── helmrelease.yaml
└── kustomization.yaml
```

## Customization

### Using This Repository as a Template

This repository is designed to be used as a template:

1. **Use GitHub's "Use this template" button** to create your own repository
2. **Clone your new repository** locally
3. **Update the Flux bootstrap command** with your GitHub username and repository name
4. **Customize the configuration** for your specific needs (see below)

### For Different Environments

To adapt this configuration for your environment:

1. **Update domains**: Replace `mkskytt.dev` with your domain
2. **Modify secrets**: Update encrypted secrets with your credentials
3. **Adjust applications**: Add, remove, or configure applications as needed
4. **Change sync settings**: Modify sync intervals in kustomization files

### Environment-Specific Configurations

Consider using Flux's multi-tenancy features for different environments:
- Separate directories for `staging/` and `production/`
- Different Git branches for environment isolation
- Tenant-specific configurations and RBAC

## Troubleshooting

### Common Issues

**Flux not syncing:**
```bash
# Check Flux status
flux get kustomizations
flux logs --follow

# Force reconciliation
flux reconcile kustomization flux-system
```

**SOPS decryption failing:**
```bash
# Verify the Age secret exists
kubectl get secret sops-age -n flux-system

# Check SOPS configuration
cat .sops.yaml
```

**Applications not deploying:**
```bash
# Check specific kustomization
flux get kustomization apps

# View detailed logs
kubectl logs -n flux-system deployment/kustomize-controller
```

**DNS records not updating:**
```bash
# Check external-dns logs
kubectl logs -n external-dns deployment/external-dns

# Verify Cloudflare credentials
kubectl get secret cloudflare-api-key -n external-dns
```

### Getting Help

- Check the [Flux CD documentation](https://fluxcd.io/flux/)
- Review application-specific documentation
- Examine logs using `kubectl logs` and `flux logs`
- Verify resource status with `kubectl describe`

## Contributing

To contribute to this cluster configuration:

1. Fork this repository
2. Create a feature branch
3. Make your changes
4. Test in a development environment
5. Submit a pull request

## License

This configuration is provided as-is for educational and operational purposes.