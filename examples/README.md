# Kubernetes Gateway API Examples

This directory contains examples for a multi-tenant Kubernetes setup using:
- **Cilium** with Gateway API
- **Cloudflared** for secure tunneling
- **External-DNS** for automatic DNS management
- **Hubble** for network observability

## Architecture

```
Internet → Cloudflare → Tunnel → Services (Direct)
```

Customer domains use CNAME records to point to your infrastructure domains:
- `myapp.com` → `app.k8s.mkskytt.dev`
- `api.myapp.com` → `api.k8s.mkskytt.dev`

## Files

### Core Configuration
- `direct-service-routing.yaml` - Main configuration for direct service routing
- `example-services.yaml` - Sample application deployments and services
- `tls-configuration.yaml` - SSL/TLS certificate management
- `gateway-api-multi-tenant-alternative.yaml` - Alternative Gateway API approach

### Documentation
- `cname-architecture.md` - Overview of the CNAME-based multi-tenant setup
- `hubble-observability.md` - Comprehensive guide to network monitoring

## Quick Start

1. **Deploy the direct service routing configuration**:
   ```bash
   kubectl apply -f direct-service-routing.yaml
   ```

2. **Deploy example services**:
   ```bash
   kubectl apply -f example-services.yaml
   ```

3. **Configure Cloudflare tunnel** to route directly to services:
   - App: `app.k8s.mkskytt.dev` → `http://my-app-service.default.svc.cluster.local:80`
   - API: `api.k8s.mkskytt.dev` → `http://my-api-service.default.svc.cluster.local:8080`
   - Dashboard: `dashboard.k8s.mkskytt.dev` → `http://dashboard-service.default.svc.cluster.local:3000`

4. **Access Hubble UI** via direct service routing at `https://hubble.k8s.mkskytt.dev`

## Adding New Customer Domains

To add a new customer domain `newcustomer.com`:

1. **Customer creates CNAME**:
   ```
   newcustomer.com  CNAME  app.k8s.mkskytt.dev
   api.newcustomer.com  CNAME  api.k8s.mkskytt.dev
   ```

2. **Configure cloudflared tunnel** to handle the new domains (they will automatically route to the same services)

3. **Monitor in Hubble** to see traffic flows
