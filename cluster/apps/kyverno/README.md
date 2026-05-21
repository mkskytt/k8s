# Kyverno Integration

This directory contains the Kyverno policy engine integration for the GitOps cluster.

## Overview

Kyverno is a policy engine designed for Kubernetes that can validate, mutate, and generate configurations using admission controllers and background controllers. It uses a declarative approach with YAML policies instead of requiring a domain-specific language.

## Components

### Core Kyverno Installation
- **namespace.yaml**: Creates the `kyverno` namespace
- **helmrelease.yaml**: Deploys Kyverno using the official Helm chart from `https://kyverno.github.io/kyverno/`
- **kustomization.yaml**: Includes all Kyverno resources for Flux management

### Kyverno Controllers
- **Admission Controller**: Validates and mutates resources during admission
- **Background Controller**: Processes existing resources for mutation and generation
- **Cleanup Controller**: Handles cleanup operations for policies
- **Reports Controller**: Generates policy violation reports

## Kyverno Configuration

The Kyverno installation is configured with:
- **Security Hardening**: Non-root containers, read-only filesystems, dropped capabilities
- **Resource Limits**: Appropriate CPU/memory limits for cluster stability  
- **Resource Filters**: Optimized filters to exclude system resources from processing
- **Multi-Controller Setup**: All controllers enabled for full functionality

## Flux Integration

Kyverno is designed to work seamlessly with Flux CD:
- **Sync Interval**: 30m to reduce reconciliation frequency
- **GitOps Workflow**: Kyverno configurations and policies are managed through Git
- **Namespace Isolation**: Dedicated namespace for Kyverno components

## Usage

### 1. Deploy Kyverno
Kyverno will be automatically deployed by Flux when these manifests are committed to the repository.

### 2. Create a Policy
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: enforce
  background: true
  rules:
  - name: check-labels
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Required labels missing"
      pattern:
        metadata:
          labels:
            app: "?*"
            version: "?*"
```

### 3. Monitor Policies
```bash
# Check Kyverno operator status
kubectl get pods -n kyverno

# View cluster policies
kubectl get clusterpolicies

# Check policy reports
kubectl get polr -A

# View cluster policy reports
kubectl get cpolr
```

## Policy Types

Kyverno supports three main policy types:

### 1. Validation Policies
Validate resource configurations against defined rules:
- **Enforce Mode**: Reject non-compliant resources
- **Audit Mode**: Log violations without blocking

### 2. Mutation Policies
Modify resources during creation or update:
- **Strategic Merge**: Add or modify fields
- **JSON Patch**: Precise field modifications
- **Overlay Pattern**: Template-based modifications

### 3. Generation Policies
Create related resources automatically:
- **ConfigMaps and Secrets**: Auto-generate configurations
- **NetworkPolicies**: Create security policies
- **RBAC**: Generate role bindings

## Common Use Cases

### Security Policies
- **Pod Security Standards**: Enforce security contexts and capabilities
- **Image Security**: Require signed images or specific registries
- **Network Policies**: Auto-generate network isolation rules

### Compliance Policies
- **Resource Labels**: Require standardized labeling
- **Resource Limits**: Enforce resource quotas
- **Naming Conventions**: Validate naming standards

### Operational Policies
- **Configuration Injection**: Add monitoring annotations
- **Backup Policies**: Auto-generate backup configurations
- **Service Mesh**: Inject sidecar configurations

## Best Practices

1. **Start with Audit Mode**: Test policies in audit mode before enforcement
2. **Use Resource Filters**: Exclude unnecessary resources for performance
3. **Monitor Policy Reports**: Regularly review policy violation reports
4. **Version Control Policies**: Store policies in Git for GitOps workflow
5. **Test Policies**: Validate policies in development environments first

## Troubleshooting

```bash
# Check Kyverno controller status
kubectl get pods -n kyverno

# View Kyverno events
kubectl get events -n kyverno

# Check specific policy status
kubectl describe clusterpolicy <policy-name>

# View admission controller logs
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller

# Check background controller logs
kubectl logs -n kyverno -l app.kubernetes.io/component=background-controller

# View policy reports for debugging
kubectl get polr -A -o wide
```

## Performance Considerations

- **Resource Filters**: Configured to exclude system namespaces and resources
- **Background Processing**: Enabled for efficient resource processing
- **Caching**: ConfigMap caching enabled for improved performance
- **Resource Limits**: Conservative limits to prevent resource exhaustion

## References

- [Kyverno Official Documentation](https://kyverno.io/docs/)
- [Kyverno Policy Library](https://kyverno.io/policies/)
- [Kyverno Best Practices](https://kyverno.io/docs/writing-policies/best-practices/)
- [GitOps and Policy Management](https://kyverno.io/docs/installation/gitops/)