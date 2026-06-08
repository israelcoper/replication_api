# ADR 0001: Use PgCat as Sidecar Connection Pooler over PgBouncer

## Status

Accepted

## Date

2026-06-08

## Context

The Rails API connects to PostgreSQL via ActiveRecord's built-in connection pool (`RAILS_MAX_THREADS=5`). The production environment runs on AWS ECS with an RDS primary and one or more read replicas.

Two requirements drove the need for an external connection pooler:

1. **Connection limiting** — ECS tasks scale horizontally; without a pooler, each task holds its own pool of persistent DB connections, exhausting RDS's connection limit under load.
2. **Read/write splitting without application logic** — routing SELECTs to the replica and writes to the primary at the infrastructure layer avoids coupling the application to replication topology.

Two candidates were evaluated:

| Feature | PgBouncer | PgCat |
|---|---|---|
| Connection pooling (transaction mode) | Yes | Yes |
| Native read/write splitting | No | Yes (SQL query parser) |
| Replica lag protection | No (app-level) | Yes (configurable threshold + ban) |
| Load balancing across replicas | No | Yes (random / round-robin) |
| Horizontal sharding | No | Yes |
| Maturity / community | High | Lower (newer project) |

Deployment pattern: PgCat runs as a **sidecar container** in the same ECS task as the Rails app. Rails connects to `127.0.0.1:6432` (PgCat), which then routes to RDS over the private VPC network. Configuration is injected at runtime via the `PGCAT_CONFIG` environment variable from Terraform templates.

`prepared_statements: false` is set in `config/database.yml` — a requirement for transaction pooling mode (applies equally to PgBouncer when using transaction pooling mode).

## Decision

Use **PgCat** as the sidecar connection pooler.

PgBouncer would satisfy the connection limiting requirement but provides no read/write splitting. Achieving equivalent routing with PgBouncer would require either AWS RDS Proxy (additional cost and latency), HAProxy with custom rules, or application-level `connects_to` configuration in Rails — all of which add operational complexity or couple the app to infrastructure concerns.

PgCat satisfies both requirements natively:

- Its SQL query parser auto-routes `SELECT` statements to replicas and writes to the primary with no application changes.
- Replica lag protection (5 MB threshold, 10 s ban) prevents stale reads during replication lag without any application-side guard.
- Transaction pooling at `pool_size=20` / `min_pool_size=5` caps RDS connections while handling spiky request patterns.

## Consequence

**Positive:**
- No `connects_to` / multi-database config needed in Rails; read/write routing is transparent.
- Replica failover and lag protection are handled at the infrastructure layer.
- PgCat's load balancer distributes read traffic evenly across replicas automatically.
- Sidecar pattern keeps network latency minimal (loopback, no extra hop).

**Negative:**
- `prepared_statements` must remain disabled in all environments (transaction pooling constraint).
- PgCat is a younger project with a smaller community than PgBouncer; breaking changes or upstream bugs carry more risk.
- PgCat configuration is TOML-based and injected via an environment variable in ECS (`terraform/templates/pgcat.toml.tftpl`), which adds a Terraform-managed indirection layer compared to a static config file.
