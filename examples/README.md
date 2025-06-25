# Kubernetes Gateway API Examples

This directory contains examples for a multi-tenant Kubernetes setup using:
- **Cilium** with Gateway API
- **Cloudflared** for secure tunneling
- **External-DNS** for automatic DNS management
- **Hubble** for network observability

## Architecture

```
Internet → Cloudflare → Tunnel → Gateway API → Services
```

Customer domains use CNAME records to point to your infrastructure domains:
- `myapp.com` → `app.k8s.mkskytt.dev`
- `api.myapp.com` → `api.k8s.mkskytt.dev`

## Files

### Core Configuration
- `gateway-api-multi-tenant.yaml` - Main Gateway and HTTPRoute configurations
- `example-services.yaml` - Sample application deployments and services
- `tls-configuration.yaml` - SSL/TLS certificate management

### Documentation
- `cname-architecture.md` - Overview of the CNAME-based multi-tenant setup
- `hubble-observability.md` - Comprehensive guide to network monitoring

## Quick Start

1. **Deploy the Gateway and HTTPRoutes**:
   ```bash
   kubectl apply -f gateway-api-multi-tenant.yaml
   ```

2. **Deploy example services**:
   ```bash
   kubectl apply -f example-services.yaml
   ```

3. **Configure Cloudflare tunnel** to route `*.k8s.mkskytt.dev` to:
   ```
   http://cilium-gateway-main-gateway.default.svc.cluster.local:80
   ```

4. **Access Hubble UI** at `https://hubble.k8s.mkskytt.dev`

## Adding New Customer Domains

To add a new customer domain `newcustomer.com`:

1. **Customer creates CNAME**:
   ```
   newcustomer.com  CNAME  app.k8s.mkskytt.dev
   ```

2. **Add to HTTPRoute**:
   ```yaml
   hostnames:
   - "app.k8s.mkskytt.dev"
   - "newcustomer.com"  # Add here
   ```

3. **Monitor in Hubble** to see traffic flows
