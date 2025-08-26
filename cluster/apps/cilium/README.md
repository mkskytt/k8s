# Cilium Integration

This directory contains the Cilium CNI integration for the GitOps cluster.

## Overview

Cilium is a CNI (Container Network Interface) plugin that provides networking, security, and observability for cloud-native environments. It leverages eBPF technology for high-performance networking and security enforcement at the kernel level.

## Components

### Core Cilium Installation
- **namespace.yaml**: Creates the `cilium` namespace
- **helmrelease.yaml**: Deploys Cilium using the official Helm chart from `https://helm.cilium.io/`
- **kustomization.yaml**: Includes all Cilium resources for Flux management

### Cilium Features
- **CNI Plugin**: Provides container networking with eBPF data plane
- **Hubble**: Network observability platform with UI and relay
- **Security Policies**: Network security enforcement with L3/L4/L7 policies
- **Gateway API**: Support for Kubernetes Gateway API
- **Load Balancing**: Service load balancing and external traffic management

## Cilium Configuration

The Cilium installation is configured with:
- **CNI Mode**: Exclusive CNI plugin replacing other networking solutions
- **Hubble Observability**: Full observability stack with UI and relay enabled
- **Gateway API**: Support for next-generation ingress management
- **L7 Proxy**: Application-level traffic management and policies
- **Resource Limits**: Appropriate CPU/memory limits for cluster stability

### Talos Linux Integration

This Cilium deployment is specifically configured for Talos Linux clusters with the following optimizations:

#### IPAM Configuration
- **Kubernetes IPAM Mode**: Uses `ipam.mode=kubernetes` as Talos assigns PodCIDRs to v1.Node resources
- **Native Integration**: Leverages Talos' built-in Kubernetes networking capabilities

#### Security Context
- **Capability Management**: Explicitly sets required capabilities while dropping `SYS_MODULE`
- **Talos Compliance**: Adheres to Talos security restrictions for kernel module loading
- **Required Capabilities**: 
  - Cilium Agent: `CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID`
  - Clean State: `NET_ADMIN,SYS_ADMIN,SYS_RESOURCE`

#### CGroup Configuration
- **Mount Reuse**: Leverages Talos' existing cgroupv2 mount at `/sys/fs/cgroup`
- **Auto-Mount Disabled**: Prevents conflicts with Talos' cgroup management
- **Optimal Performance**: Reduces overhead by reusing system mounts

#### Kube-Proxy Replacement
- **KubePrism Integration**: Uses Talos' KubePrism for Kubernetes API access
- **Local Endpoint**: Configured to use `localhost:7445` for reliable cluster communication
- **Complete Replacement**: Replaces kube-proxy functionality with eBPF implementation

#### DNS Compatibility
- **Host Legacy Routing**: Enables `bpf.hostLegacyRouting=true` for DNS compatibility
- **Talos DNS Forwarding**: Compatible with Talos' host DNS forwarding feature (enabled by default since Talos 1.8+)

## Flux Integration

Cilium is designed to work seamlessly with Flux CD:
- **Sync Interval**: 30m to reduce reconciliation frequency
- **GitOps Workflow**: Cilium configurations are managed through Git like other resources
- **Namespace Isolation**: Dedicated namespace for Cilium components

## Usage

### 1. Deploy Cilium
Cilium will be automatically deployed by Flux when these manifests are committed to the repository.

### 2. Verify Installation
```bash
# Check Cilium operator status
kubectl get pods -n cilium

# Verify Cilium connectivity
cilium connectivity test

# Check Hubble status
kubectl get pods -n cilium -l k8s-app=hubble-relay

# Access Hubble UI (if enabled)
kubectl port-forward -n cilium svc/hubble-ui 12000:80
```

### 3. Network Policies
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: demo-policy
  namespace: default
spec:
  endpointSelector:
    matchLabels:
      app: demo
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
```

## Network Features

### CNI Capabilities
- **eBPF Data Plane**: High-performance networking with kernel-level packet processing
- **IP Address Management**: Automatic IP allocation and management
- **Service Mesh Ready**: Native support for service mesh architectures
- **Multi-Cluster**: Support for multi-cluster networking scenarios

### Security Features
- **Network Segmentation**: Micro-segmentation with granular policies
- **Identity-Based Security**: Security based on workload identity, not IP addresses
- **Encryption**: Transparent encryption for pod-to-pod communication
- **Threat Detection**: Runtime security monitoring and anomaly detection

## Observability

### Hubble Integration
- **Network Flow Monitoring**: Real-time network flow visibility
- **Service Dependency Mapping**: Automatic service topology discovery
- **Performance Metrics**: Network performance and latency monitoring
- **Security Insights**: Security policy violations and threat detection

### Monitoring Commands
```bash
# Monitor network flows
hubble observe

# Check service dependencies
hubble observe --type drop

# View network policies
kubectl get ciliumnetworkpolicies -A

# Check Cilium agent logs
kubectl logs -n cilium -l k8s-app=cilium
```

## Best Practices

1. **CNI Replacement**: Ensure no other CNI plugins are installed before deploying Cilium
2. **Resource Allocation**: Provision adequate resources for eBPF map storage
3. **Network Policies**: Start with permissive policies and gradually tighten security
4. **Monitoring**: Use Hubble for continuous network observability
5. **Cluster Mesh**: Consider cluster mesh for multi-cluster deployments

## Troubleshooting

```bash
# Check Cilium status
cilium status

# Verify connectivity
cilium connectivity test

# Check eBPF maps
cilium map list

# Debug network policies
cilium policy get

# View Cilium configuration
kubectl get ciliumconfig -o yaml
```

## Performance Considerations

- **eBPF Memory**: Monitor eBPF map memory usage in large clusters
- **CPU Resources**: Allocate sufficient CPU for packet processing
- **Hubble Impact**: Hubble observability has minimal performance overhead
- **Policy Complexity**: Complex L7 policies may impact performance

## References

- [Cilium Official Documentation](https://cilium.io/docs/)
- [Cilium Network Policies](https://docs.cilium.io/en/stable/security/policy/)
- [Hubble Observability](https://github.com/cilium/hubble)
- [Cilium Gateway API](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/)