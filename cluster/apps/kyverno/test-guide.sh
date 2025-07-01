#!/bin/bash
# Kyverno Policy Validation Script
# This script demonstrates how to test Kyverno policies using dry-run

echo "=== Kyverno Policy Testing ==="
echo "This script shows how to test the Kyverno policies once deployed."
echo ""

echo "1. Testing validation policies:"
echo "   - Apply test-pods.yaml to see policy enforcement"
echo "   - The 'bad' pod should be rejected for missing labels"
echo "   - The 'good' pod should be accepted and mutated"
echo ""

echo "2. Check policy reports:"
echo "   kubectl get cpol -A"
echo "   kubectl get polr -A"
echo ""

echo "3. Monitor Kyverno:"
echo "   kubectl get pods -n kyverno"
echo "   kubectl logs -n kyverno deployment/kyverno-admission-controller"
echo ""

echo "4. Test namespace generation:"
echo "   kubectl create namespace test-namespace"
echo "   kubectl get networkpolicy,limitrange,resourcequota -n test-namespace"
echo ""

echo "For more details, see: cluster/apps/kyverno/README.md"