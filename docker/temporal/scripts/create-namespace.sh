#!/bin/sh
set -e

temporal operator namespace create \
  --address "${TEMPORAL_ADDRESS}" \
  --namespace "${DEFAULT_NAMESPACE:-default}" || true

echo "Namespace '${DEFAULT_NAMESPACE:-default}' created."
