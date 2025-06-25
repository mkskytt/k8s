# CNAME Architecture with Cilium Gateway API

## Overview
This setup uses Kubernetes Gateway API with Cilium to provide customers with their own domains while maintaining centralized infrastructure.

## Architecture

```
Customer Domain          Primary Infrastructure Domain
myapp.com           →    app.k8s.mkskytt.dev
api.myapp.com       →    api.k8s.mkskytt.dev
dashboard.myapp.com →    dashboard.k8s.mkskytt.dev
```

## DNS Configuration

### Your DNS (Cloudflare - Automatic via External-DNS)
```
app.k8s.mkskytt.dev      A/CNAME  → Cloudflare tunnel
api.k8s.mkskytt.dev      A/CNAME  → Cloudflare tunnel
dashboard.k8s.mkskytt.dev A/CNAME → Cloudflare tunnel
hubble.k8s.mkskytt.dev   A/CNAME  → Cloudflare tunnel (internal)
```

### Customer DNS (Customer manages)
```
myapp.com               CNAME → app.k8s.mkskytt.dev
api.myapp.com           CNAME → api.k8s.mkskytt.dev
dashboard.myapp.com     CNAME → dashboard.k8s.mkskytt.dev
```

## Cloudflare Tunnel Configuration

In your Cloudflare dashboard, configure a wildcard route:

| Subdomain | Domain | Service Type | URL |
|-----------|--------|--------------|-----|
| * | k8s.mkskytt.dev | HTTP | http://cilium-gateway-main-gateway.default.svc.cluster.local:80 |

### Service Configuration Note

The `cilium-gateway-main-gateway` service is created in the Gateway API configuration to expose the Cilium Gateway for external access. This service:

- Provides the endpoint that cloudflared tunnel connects to
- Routes traffic to the Cilium Gateway proxy pods 
- Uses selectors to automatically target the correct Gateway infrastructure
- Enables cloudflared to reach the Gateway API from outside the cluster

Without this service, cloudflared would not be able to route traffic to the Gateway, even though the Gateway itself is properly configured.

## Gateway API Benefits

✅ **Modern Kubernetes standard** - Future-proof API
✅ **Rich traffic management** - Advanced routing, filters, policies
✅ **Multi-protocol support** - HTTP, HTTPS, TCP, UDP
✅ **Vendor neutral** - Portable across different implementations
✅ **Extensible** - Custom filters and policies
✅ **Type-safe configuration** - Strong API contracts

## Benefits

✅ **Customer branding** - They use their own domain  
✅ **Simple setup** - Just one CNAME record per subdomain  
✅ **Centralized SSL** - You handle all certificates  
✅ **Easy migration** - Change backend without customer DNS changes  
✅ **Monitoring** - All traffic flows through your infrastructure  

## Customer Instructions

To set up a custom domain, customers need to:

1. **Add CNAME records** in their DNS:
   ```
   myapp.com           CNAME   app.k8s.mkskytt.dev
   api.myapp.com       CNAME   api.k8s.mkskytt.dev
   dashboard.myapp.com CNAME   dashboard.k8s.mkskytt.dev
   ```

2. **Notify you** to add their domain to the HTTPRoute hostnames

3. **Wait for DNS propagation** (usually 5-60 minutes)

4. **Test the setup**:
   ```bash
   curl -v https://myapp.com
   curl -v https://api.myapp.com
   ```

## Gateway API Configuration

Example HTTPRoute for new customer:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-routes
spec:
  parentRefs:
  - name: main-gateway
  hostnames:
  - "app.k8s.mkskytt.dev"
  - "myapp.com"          # Add customer domain here
  - "newcustomer.io"     # Add new customer domains
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: my-app-service
      port: 80
```

## Hubble Observability

Access Hubble UI for traffic monitoring:
- **URL**: https://hubble.k8s.mkskytt.dev
- **Features**: 
  - Real-time traffic flow visualization
  - DNS query monitoring
  - Network policy enforcement
  - Performance metrics per customer domain

## SSL/TLS Handling

- **Option 1**: Cloudflare handles SSL for all domains (recommended)
- **Option 2**: Use cert-manager with DNS-01 challenges for wildcard certificates
- **Option 3**: Customer provides certificates via Kubernetes secrets
