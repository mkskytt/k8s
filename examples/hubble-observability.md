# Hubble Observability with Gateway API

## Overview
Hubble provides deep network observability for your Cilium-powered Gateway API setup, giving you insights into traffic flows, DNS resolution, and security policies.

## Hubble Components

### 1. Hubble Agent
- **Embedded in Cilium** - No additional overhead
- **eBPF-based** - Kernel-level visibility
- **Real-time metrics** - Live traffic monitoring

### 2. Hubble Relay
- **Aggregates data** from all nodes
- **gRPC API** - For programmatic access
- **Scalable architecture** - Multi-node clusters

### 3. Hubble UI
- **Web interface** - Visual traffic flow
- **Service map** - Real-time topology
- **Search & filter** - Find specific flows

## Accessing Hubble

### Method 1: Through Gateway API (Recommended)
Access via your configured route:
```
https://hubble.k8s.mkskytt.dev
```

### Method 2: Port Forwarding
```bash
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# Visit http://localhost:12000
```

### Method 3: CLI Access
```bash
# Install Hubble CLI
curl -L --fail --remote-name-all https://github.com/cilium/hubble/releases/latest/download/hubble-linux-amd64.tar.gz
tar xzvfC hubble-linux-amd64.tar.gz /usr/local/bin
rm hubble-linux-amd64.tar.gz

# Port forward to Hubble Relay
kubectl port-forward -n kube-system svc/hubble-relay 4245:80

# Observe flows
hubble observe --server localhost:4245
```

## Key Monitoring Capabilities

### 1. Multi-Tenant Traffic Analysis
Monitor traffic per customer domain:
```bash
# Filter by specific customer domain
hubble observe --http-header "host: myapp.com"

# Monitor API traffic
hubble observe --http-path "/api"

# Check DNS resolution for customer domains
hubble observe --type dns --to-domain myapp.com
```

### 2. Performance Monitoring
```bash
# HTTP response codes
hubble observe --http-status 200,300,400,500

# Latency analysis
hubble observe --http-header "x-response-time"

# Connection failures
hubble observe --verdict DROPPED
```

### 3. Security Monitoring
```bash
# Monitor policy drops
hubble observe --verdict DENIED

# TLS connection analysis
hubble observe --type tls

# Monitor for suspicious patterns
hubble observe --http-method POST,PUT,DELETE
```

## Metrics Integration

### Prometheus Metrics
Hubble exports metrics that can be scraped by Prometheus:

```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: hubble-metrics
spec:
  selector:
    matchLabels:
      k8s-app: hubble
  endpoints:
  - port: hubble-metrics
```

### Key Metrics
- `hubble_flows_total` - Total network flows
- `hubble_tcp_flags_total` - TCP flag distribution  
- `hubble_dns_queries_total` - DNS query patterns
- `hubble_http_requests_total` - HTTP request metrics
- `hubble_drop_total` - Dropped packet analysis

## Dashboard Examples

### 1. Customer Traffic Overview
Monitor traffic per customer domain with Grafana dashboard:
```json
{
  "query": "rate(hubble_http_requests_total{destination_domain=~\".*k8s.mkskytt.dev\"}[5m])",
  "legend": "{{destination_domain}}"
}
```

### 2. API Performance
Track API response times and error rates:
```json
{
  "query": "histogram_quantile(0.95, rate(hubble_http_request_duration_seconds_bucket{http_path=~\"/api.*\"}[5m]))",
  "legend": "95th percentile latency"
}
```

### 3. Security Alerts
Monitor for potential security issues:
```json
{
  "query": "rate(hubble_drop_total{reason=\"Policy denied\"}[5m])",
  "legend": "Policy violations"
}
```

## Network Policies with Hubble

Use Hubble to verify network policy enforcement:

```yaml
# Example: Isolate customer traffic
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: customer-isolation
spec:
  endpointSelector:
    matchLabels:
      app: my-app
  ingress:
  - fromEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: default
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
```

Monitor policy enforcement:
```bash
hubble observe --type policy-verdict --verdict DENIED
```

## Troubleshooting with Hubble

### 1. DNS Resolution Issues
```bash
# Check DNS queries for customer domains
hubble observe --type dns --to-domain myapp.com

# Monitor DNS failures
hubble observe --type dns --verdict DROPPED
```

### 2. Connection Problems
```bash
# Monitor TCP connection establishment
hubble observe --type tcp --tcp-flag SYN

# Check for connection resets
hubble observe --type tcp --tcp-flag RST
```

### 3. HTTP Issues
```bash
# Monitor HTTP errors
hubble observe --http-status 4xx,5xx

# Check specific customer traffic
hubble observe --http-header "host: myapp.com" --http-status 5xx
```

## Integration with GitOps

Monitor your Gateway API deployments:
```bash
# Watch for new HTTPRoute deployments
hubble observe --type trace --trace-id gateway-api

# Monitor configuration changes
kubectl get gateways,httproutes -o yaml | grep -A5 -B5 "myapp.com"
```

This comprehensive observability setup gives you deep insights into your multi-tenant Gateway API infrastructure!
