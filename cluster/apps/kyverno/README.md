# Kyverno Policy Management

This directory contains the Kyverno installation and policy definitions for Kubernetes policy management, governance, and security.

## Overview

Kyverno is a policy engine designed for Kubernetes that enables:
- **Validation**: Enforce compliance and security rules
- **Mutation**: Automatically modify resources to apply defaults and best practices
- **Generation**: Create additional resources automatically

## Installation

Kyverno is deployed using Helm via FluxCD with the following components:
- Admission Controller (replicas: 1)
- Background Controller (enabled)
- Cleanup Controller (enabled)  
- Reports Controller (enabled)
- Metrics Service (enabled)

## Implemented Policies

### Validation Policies (`validation-policies.yaml`)

#### 1. Require Labels (`require-labels`)
- **Purpose**: Ensures all Pods and Deployments have required organizational labels
- **Required Labels**: `app`, `version`, `environment`
- **Severity**: Medium
- **Action**: Enforce (blocks non-compliant resources)

#### 2. Restrict Privileged Containers (`restrict-privileged-containers`)
- **Purpose**: Prevents creation of privileged containers
- **Applies to**: Pods
- **Severity**: High
- **Action**: Enforce (blocks privileged containers)

#### 3. Restrict Host Network (`restrict-host-network`)
- **Purpose**: Prevents Pods from using host network
- **Applies to**: Pods  
- **Severity**: High
- **Action**: Enforce (blocks host network usage)

### Mutation Policies (`mutation-policies.yaml`)

#### 1. Add Default Resources (`add-default-resources`)
- **Purpose**: Automatically adds resource limits and requests to containers
- **Default Limits**: CPU: 500m, Memory: 512Mi
- **Default Requests**: CPU: 100m, Memory: 128Mi
- **Applies to**: Pods, Deployments

#### 2. Add Security Context (`add-security-context`)
- **Purpose**: Adds security context settings for improved security posture
- **Pod Security Context**: 
  - `runAsNonRoot: true`
  - `runAsUser: 1000`
  - `fsGroup: 2000`
- **Container Security Context**:
  - `allowPrivilegeEscalation: false`
  - `readOnlyRootFilesystem: true`
  - `capabilities.drop: [ALL]`

#### 3. Add Environment Label (`add-environment-label`)
- **Purpose**: Adds default `environment: development` label if not specified
- **Applies to**: Pods, Deployments, Services

### Generation Policies (`generation-policies.yaml`)

#### 1. Generate Default Network Policy (`generate-default-network-policy`)
- **Purpose**: Creates a default-deny-ingress network policy for new namespaces
- **Policy**: Denies all ingress traffic by default (least privilege)
- **Excluded Namespaces**: System namespaces (kube-system, flux-system, etc.)

#### 2. Generate Default Limit Range (`generate-default-limit-range`)
- **Purpose**: Creates default resource limits for new namespaces
- **Container Limits**:
  - Default: CPU: 500m, Memory: 512Mi
  - Default Requests: CPU: 100m, Memory: 128Mi
  - Max: CPU: 2, Memory: 2Gi
  - Min: CPU: 50m, Memory: 64Mi

#### 3. Generate Resource Quota (`generate-resource-quota`)
- **Purpose**: Creates resource quotas to prevent resource overconsumption
- **Quotas**:
  - CPU Requests: 4 cores, Limits: 8 cores
  - Memory Requests: 8Gi, Limits: 16Gi
  - PVCs: 10, Pods: 20, Services: 10

## Policy Categories

- **Security**: Container privilege restrictions, network isolation
- **Best Practices**: Resource management, labeling standards
- **Resource Management**: Quotas, limits, and requests

## Integration

Kyverno integrates with:
- **FluxCD**: GitOps deployment and management
- **Kubernetes RBAC**: Policy enforcement
- **Metrics**: Prometheus-compatible metrics endpoint
- **Reports**: Policy violation reporting

## Monitoring

Kyverno provides:
- Policy violation reports
- Metrics endpoint for monitoring
- Background scanning for existing resources
- Audit mode capabilities

## Customization

To customize policies:
1. Modify the policy YAML files in the `policies/` directory
2. Commit changes to trigger GitOps deployment
3. Monitor policy reports for compliance status

For development environments, consider setting `validationFailureAction: Audit` to log violations without blocking resources.