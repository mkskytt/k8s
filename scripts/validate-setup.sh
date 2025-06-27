#!/bin/bash

# Cloudflare Tunnel and Podinfo Validation Script
# This script validates that the Cloudflare Tunnel setup is correctly configured
# to route traffic to the stefanprodan/podinfo demo application.

set -e

echo "🔍 Validating Cloudflare Tunnel and Podinfo Setup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "OK")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "INFO")
            echo -e "${YELLOW}ℹ️  $message${NC}"
            ;;
    esac
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_status "ERROR" "kubectl not found. Please install kubectl to run this validation."
    exit 1
fi

# Check cluster connection
if timeout 5 kubectl cluster-info &> /dev/null; then
    print_status "OK" "Connected to Kubernetes cluster"
    CLUSTER_AVAILABLE=true
else
    print_status "WARN" "Cannot connect to Kubernetes cluster. Some checks will be skipped."
    CLUSTER_AVAILABLE=false
fi

echo ""
echo "📋 Configuration Validation"
echo "=========================="

# Validate YAML files
if python3 -c "
import yaml
try:
    with open('cluster/apps/cloudflared/helmrelease.yaml', 'r') as f:
        docs = list(yaml.safe_load_all(f))
        print('OK: Cloudflared HelmRelease YAML is valid')
    with open('cluster/apps/demo-app/helmrelease.yaml', 'r') as f:
        docs = list(yaml.safe_load_all(f))
        print('OK: Demo-app HelmRelease YAML is valid')
except Exception as e:
    print(f'ERROR: YAML validation failed: {e}')
    exit(1)
" 2>/dev/null; then
    print_status "OK" "All YAML files are syntactically valid"
else
    print_status "ERROR" "YAML validation failed"
    exit 1
fi

# Check tunnel configuration
TUNNEL_CONFIG=$(grep -A 10 "ingress:" cluster/apps/cloudflared/helmrelease.yaml || true)
if echo "$TUNNEL_CONFIG" | grep -q "demo.k8s.mkskytt.dev"; then
    print_status "OK" "Tunnel hostname configured for demo.k8s.mkskytt.dev"
    
    if echo "$TUNNEL_CONFIG" | grep -q "demo-app.demo-app.svc.cluster.local:9898"; then
        print_status "OK" "Tunnel routes to correct service: demo-app.demo-app.svc.cluster.local:9898"
    else
        print_status "ERROR" "Tunnel service name is incorrect - should be demo-app.demo-app.svc.cluster.local:9898"
        exit 1
    fi
else
    print_status "ERROR" "Demo hostname not found in tunnel configuration"
    exit 1
fi

# Check podinfo configuration
PODINFO_CONFIG=$(cat cluster/apps/demo-app/helmrelease.yaml)
if echo "$PODINFO_CONFIG" | grep -q "stefanprodan/podinfo"; then
    print_status "OK" "Podinfo uses correct image: stefanprodan/podinfo"
else
    print_status "ERROR" "Podinfo image configuration is incorrect"
    exit 1
fi

if echo "$PODINFO_CONFIG" | grep -q "port: 9898"; then
    print_status "OK" "Podinfo service port is correctly configured (9898)"
else
    print_status "ERROR" "Podinfo service port configuration is incorrect"
    exit 1
fi

echo ""

if [ "$CLUSTER_AVAILABLE" = true ]; then
    echo "🔧 Cluster Resource Validation"
    echo "============================="
    
    # Check namespace
    if kubectl get namespace demo-app &> /dev/null; then
        print_status "OK" "demo-app namespace exists"
    else
        print_status "WARN" "demo-app namespace does not exist (may not be deployed yet)"
    fi
    
    # Check cloudflared namespace
    if kubectl get namespace cloudflared &> /dev/null; then
        print_status "OK" "cloudflared namespace exists"
    else
        print_status "WARN" "cloudflared namespace does not exist (may not be deployed yet)"
    fi
    
    # Check if HelmReleases exist
    if kubectl get helmrelease demo-app -n demo-app &> /dev/null; then
        print_status "OK" "demo-app HelmRelease exists"
        
        # Check HelmRelease status
        HELM_STATUS=$(kubectl get helmrelease demo-app -n demo-app -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [ "$HELM_STATUS" = "True" ]; then
            print_status "OK" "demo-app HelmRelease is ready"
        else
            print_status "WARN" "demo-app HelmRelease status: $HELM_STATUS"
        fi
    else
        print_status "WARN" "demo-app HelmRelease not found (may not be deployed yet)"
    fi
    
    if kubectl get helmrelease cloudflared -n cloudflared &> /dev/null; then
        print_status "OK" "cloudflared HelmRelease exists"
        
        # Check HelmRelease status
        HELM_STATUS=$(kubectl get helmrelease cloudflared -n cloudflared -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [ "$HELM_STATUS" = "True" ]; then
            print_status "OK" "cloudflared HelmRelease is ready"
        else
            print_status "WARN" "cloudflared HelmRelease status: $HELM_STATUS"
        fi
    else
        print_status "WARN" "cloudflared HelmRelease not found (may not be deployed yet)"
    fi
    
    # Check services
    if kubectl get service demo-app -n demo-app &> /dev/null; then
        print_status "OK" "demo-app service exists"
        
        # Check service ports
        SERVICE_PORT=$(kubectl get service demo-app -n demo-app -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "Unknown")
        if [ "$SERVICE_PORT" = "9898" ]; then
            print_status "OK" "demo-app service exposes correct port (9898)"
        else
            print_status "WARN" "demo-app service port: $SERVICE_PORT (expected: 9898)"
        fi
    else
        print_status "WARN" "demo-app service not found (may not be deployed yet)"
    fi
else
    print_status "INFO" "Cluster validation skipped (no cluster connection)"
fi

echo ""
echo "🌐 External Connectivity Test"
echo "============================"

# Test external URL
if command -v curl &> /dev/null; then
    print_status "INFO" "Testing external URL: https://demo.k8s.mkskytt.dev"
    
    if curl -s --max-time 10 --head https://demo.k8s.mkskytt.dev | head -1 | grep -q "200\|301\|302"; then
        print_status "OK" "External URL is accessible"
    else
        print_status "WARN" "External URL test failed (tunnel may not be configured in Cloudflare yet)"
    fi
else
    print_status "WARN" "curl not available - skipping external connectivity test"
fi

echo ""
echo "📝 Summary"
echo "=========="

print_status "INFO" "Configuration validation completed"
print_status "INFO" "If all checks pass, the Cloudflare Tunnel should route demo.k8s.mkskytt.dev to podinfo"
print_status "INFO" "External access requires Cloudflare tunnel to be properly configured in Cloudflare dashboard"

echo ""
echo "🔗 Next Steps:"
echo "- Deploy the configuration: kubectl apply -k cluster/apps/"
echo "- Check Flux reconciliation: kubectl get helmreleases -A"
echo "- Test external access: curl https://demo.k8s.mkskytt.dev"
echo "- Monitor with Hubble: https://hubble.k8s.mkskytt.dev"