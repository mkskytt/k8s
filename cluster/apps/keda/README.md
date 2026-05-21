# KEDA Integration

This directory contains the KEDA (Kubernetes Event-Driven Autoscaling) integration for the GitOps cluster.

## Overview

KEDA enables event-driven autoscaling for Kubernetes workloads, allowing applications to scale based on external metrics, queues, databases, and other event sources rather than just CPU/memory metrics.

## Components

### Core KEDA Installation
- **namespace.yaml**: Creates the `keda` namespace
- **helmrelease.yaml**: Deploys KEDA using the official Helm chart from `https://kedacore.github.io/charts`
- **kustomization.yaml**: Includes all KEDA resources for Flux management

### Example Configurations
- **example-scaledobject.yaml**: Basic CPU-based scaling example with an nginx deployment
- **advanced-examples.yaml**: Advanced event-driven scaling examples including:
  - Queue-based scaling (RabbitMQ)
  - Prometheus metrics scaling
  - Kafka consumer lag scaling
  - HTTP request-based scaling
  - Cron-based predictable scaling

## KEDA Configuration

The KEDA installation is configured with:
- **Operator**: Manages ScaledObjects and ScaledJobs
- **Metrics Server**: Provides custom metrics to Kubernetes HPA
- **Admission Webhooks**: Validates KEDA resources
- **Resource Limits**: Appropriate CPU/memory limits for cluster stability

## Flux Integration

KEDA is designed to work seamlessly with Flux CD:
- **Sync Interval**: 30m to reduce reconciliation frequency
- **No Replica Management**: Flux does not manage replica counts for scaled workloads
- **GitOps Workflow**: KEDA configurations are managed through Git like other resources

## Usage

### 1. Deploy KEDA
KEDA will be automatically deployed by Flux when these manifests are committed to the repository.

### 2. Create a ScaledObject
```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: my-app-scaler
  namespace: my-namespace
spec:
  scaleTargetRef:
    name: my-deployment
  minReplicaCount: 0
  maxReplicaCount: 10
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus:9090
      metricName: my_custom_metric
      threshold: '5'
      query: avg(my_custom_metric)
```

### 3. Monitor Scaling
```bash
# Check KEDA operator status
kubectl get pods -n keda

# View ScaledObjects
kubectl get scaledobjects -A

# Check HPA created by KEDA
kubectl get hpa -A

# View KEDA operator logs
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator
```

## Scaling Triggers

KEDA supports 60+ scalers including:
- **Message Queues**: RabbitMQ, Apache Kafka, Azure Service Bus, AWS SQS
- **Databases**: PostgreSQL, MySQL, Redis, MongoDB
- **Cloud Services**: AWS CloudWatch, Azure Monitor, GCP Pub/Sub
- **Custom Metrics**: Prometheus, external HTTP endpoints
- **Scheduled**: Cron-based scaling for predictable workloads

## Best Practices

1. **Start with minReplicaCount: 0** for true event-driven scaling
2. **Set appropriate maxReplicaCount** to prevent resource exhaustion
3. **Use TriggerAuthentication** for secure access to external systems
4. **Configure scaling behavior** to prevent rapid scaling oscillations
5. **Monitor scaling metrics** to tune thresholds appropriately

## Troubleshooting

```bash
# Check KEDA operator status
kubectl get pods -n keda

# View KEDA events
kubectl get events -n keda

# Check ScaledObject status
kubectl describe scaledobject <name> -n <namespace>

# View scaling activity
kubectl describe hpa keda-hpa-<scaledobject-name> -n <namespace>

# Check KEDA metrics server
kubectl logs -n keda -l app.kubernetes.io/name=keda-metrics-apiserver
```

## References

- [KEDA Official Documentation](https://keda.sh/docs/)
- [KEDA Scalers](https://keda.sh/docs/latest/scalers/)
- [Flux and KEDA Integration](https://github.com/fluxcd/flux2/discussions/4007)