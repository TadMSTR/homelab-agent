#!/bin/sh
set -e

# postgres is guaranteed healthy by depends_on condition — no wait loop needed.
# Use || true on create-database so a restart (db already exists) doesn't abort.

# Create and migrate default store
temporal-sql-tool \
  --plugin postgres12 \
  --ep temporal-postgresql \
  --port 5432 \
  -u temporal \
  --pw "${SQL_PASSWORD}" \
  create-database --defaultdb postgres temporal || true

temporal-sql-tool \
  --plugin postgres12 \
  --ep temporal-postgresql \
  --port 5432 \
  -u temporal \
  --pw "${SQL_PASSWORD}" \
  --db temporal \
  setup-schema -v 0.0

temporal-sql-tool \
  --plugin postgres12 \
  --ep temporal-postgresql \
  --port 5432 \
  -u temporal \
  --pw "${SQL_PASSWORD}" \
  --db temporal \
  update-schema -d /etc/temporal/schema/postgresql/v12/temporal/versioned

# Create and migrate visibility store
temporal-sql-tool \
  --plugin postgres12 \
  --ep temporal-postgresql \
  --port 5432 \
  -u temporal \
  --pw "${SQL_PASSWORD}" \
  create-database --defaultdb temporal temporal_visibility || true

temporal-sql-tool \
  --plugin postgres12 \
  --ep temporal-postgresql \
  --port 5432 \
  -u temporal \
  --pw "${SQL_PASSWORD}" \
  --db temporal_visibility \
  setup-schema -v 0.0

temporal-sql-tool \
  --plugin postgres12 \
  --ep temporal-postgresql \
  --port 5432 \
  -u temporal \
  --pw "${SQL_PASSWORD}" \
  --db temporal_visibility \
  update-schema -d /etc/temporal/schema/postgresql/v12/visibility/versioned

echo "Schema setup complete."
