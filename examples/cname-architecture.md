# CNAME Architecture with Direct Service Routing

## Overview
This setup uses direct service routing with cloudflared tunnels to provide customers with their own domains while maintaining centralized infrastructure. Traffic flows directly from cloudflared to individual Kubernetes services without an ingress controller layer.

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

In your Cloudflare dashboard, configure separate routes for each service:

| Subdomain | Domain | Service Type | URL |
|-----------|--------|--------------|-----|
| app | k8s.mkskytt.dev | HTTP | http://my-app-service.default.svc.cluster.local:80 |
| api | k8s.mkskytt.dev | HTTP | http://my-api-service.default.svc.cluster.local:8080 |
| dashboard | k8s.mkskytt.dev | HTTP | http://dashboard-service.default.svc.cluster.local:3000 |
| hubble | k8s.mkskytt.dev | HTTP | http://hubble-ui.kube-system.svc.cluster.local:80 |

## Direct Service Routing Benefits

✅ **Simplified architecture** - No ingress controller layer
✅ **Direct traffic flow** - Reduced latency and complexity  
✅ **Per-service control** - Individual routing configuration
✅ **Easy debugging** - Clear traffic path from tunnel to service
✅ **Flexible scaling** - Services can be scaled independently
✅ **Resource efficient** - No additional ingress controller resources

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

2. **Notify you** to add new cloudflared tunnel routes for their domain

3. **Wait for DNS propagation** (usually 5-60 minutes)

4. **Test the setup**:
   ```bash
   curl -v https://myapp.com
   curl -v https://api.myapp.com
   ```

## Service Routing Configuration

With direct service routing, cloudflared handles hostname-based routing. Customer CNAMEs point to your infrastructure domains, and cloudflared routes each subdomain to the appropriate service:

```yaml
# Example services that cloudflared routes to:
apiVersion: v1
kind: Service
metadata:
  name: my-app-service
spec:
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: v1  
kind: Service
metadata:
  name: my-api-service
spec:
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: Service  
metadata:
  name: dashboard-service
spec:
  ports:
  - port: 3000
    targetPort: 3000
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
