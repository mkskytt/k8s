# Podinfo Demo with Cloudflare Tunnel

This document demonstrates how the Cloudflare Tunnel is configured to work as ingress for the stefanprodan/podinfo demo application.

## Overview

The setup uses Cloudflare Tunnel to route external traffic directly to Kubernetes services without requiring a traditional ingress controller.

## Architecture

```
Internet → Cloudflare → Cloudflare Tunnel → podinfo Service
```

## Configuration

### Demo Application
- **Chart**: stefanprodan/podinfo v6.7.0
- **Release Name**: demo-app
- **Namespace**: demo-app
- **Service**: demo-app.demo-app.svc.cluster.local:9898

### Tunnel Routing
- **External URL**: https://demo.k8s.mkskytt.dev
- **Internal Target**: http://demo-app.demo-app.svc.cluster.local:9898

## Deployment

The application is deployed using Flux GitOps:

1. **HelmRepository**: Configured to pull from stefanprodan's podinfo chart repository
2. **HelmRelease**: Deploys podinfo with custom configuration
3. **Cloudflared**: Routes external traffic to the service

## Testing

### Verify Service Availability
```bash
# Check if the demo-app service exists
kubectl get service demo-app -n demo-app

# Check if pods are running
kubectl get pods -n demo-app

# Check service endpoints
kubectl get endpoints demo-app -n demo-app
```

### Test External Access
```bash
# Test external access through Cloudflare Tunnel
curl -I https://demo.k8s.mkskytt.dev

# Test specific podinfo endpoints
curl https://demo.k8s.mkskytt.dev/api/info
curl https://demo.k8s.mkskytt.dev/healthz
```

### Expected Response
The podinfo application should respond with:
- Status page at the root URL
- JSON info at `/api/info`
- Health check at `/healthz`
- Version and runtime information

## Troubleshooting

### Common Issues

1. **Service Name Mismatch**
   - Ensure tunnel routes to correct service name: `demo-app` (not `demo-app-podinfo`)

2. **Port Configuration**
   - Podinfo runs on port 9898 by default
   - Service should expose port 9898

3. **DNS Resolution**
   - Verify the tunnel can resolve the service DNS name
   - Check cluster DNS is working

### Debug Commands
```bash
# Check cloudflared logs
kubectl logs -n cloudflared -l app.kubernetes.io/name=cloudflared

# Check demo-app logs
kubectl logs -n demo-app -l app.kubernetes.io/name=podinfo

# Port forward for local testing
kubectl port-forward -n demo-app svc/demo-app 8080:9898
# Then test: curl http://localhost:8080
```

## Configuration Files

- `cluster/apps/cloudflared/helmrelease.yaml` - Tunnel configuration
- `cluster/apps/demo-app/helmrelease.yaml` - Podinfo deployment
- `cluster/apps/demo-app/helmrepository.yaml` - Chart repository

## Security

- Traffic is encrypted via Cloudflare's edge
- No external load balancer or NodePort required
- Service remains internal to the cluster
- Zero Trust access can be configured in Cloudflare dashboard