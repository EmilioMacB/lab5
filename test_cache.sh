#!/bin/bash
API_URL="https://v5k5778e2c.execute-api.us-east-1.amazonaws.com/prod/metrics"

echo "=========================================================="
echo "Identidad del estudiante:"
aws sts get-caller-identity --query "Arn" --output text
echo "=========================================================="

echo ""
echo "--- 1. MEDICION SIN CACHE (Cache Bypass / Cold Requests) ---"
for i in {1..5}; do
  METRICS=$(curl -s -o /dev/null -w "TTFB: %{time_starttransfer}s | Total: %{time_total}s" -H "Cache-Control: no-cache" "$API_URL")
  echo "Peticion $i (Sin cache): $METRICS"
done

echo ""
echo "--- 2. MEDICION CON CACHE CARGADA (Warm Cache Hits) ---"
# Warmup request
curl -s -o /dev/null "$API_URL"

for i in {1..5}; do
  METRICS=$(curl -s -o /dev/null -w "TTFB: %{time_starttransfer}s | Total: %{time_total}s" "$API_URL")
  echo "Peticion $i (Con cache): $METRICS"
done
echo "=========================================================="
