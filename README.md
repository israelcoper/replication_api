# Replication API

A Rails API demonstrating PostgreSQL primary/replica streaming replication with [PgCat](https://github.com/postgresml/pgcat) as an automatic read/write splitting connection pooler.

## Architecture

### System Context

```mermaid
graph LR
  linkStyle default fill:#ffffff

  subgraph diagram ["System Context View: Replication API"]
    style diagram fill:#ffffff,stroke:#ffffff

    1["<div style='font-weight: bold'>Developer</div><div style='font-size: 70%; margin-top: 0px'>[Person]</div><div style='font-size: 80%; margin-top:10px'>Interacts with the API<br />locally or via the load<br />balancer</div>"]
    style 1 fill:#ffffff,stroke:#444444,color:#444444
    2["<div style='font-weight: bold'>Replication API</div><div style='font-size: 70%; margin-top: 0px'>[Software System]</div><div style='font-size: 80%; margin-top:10px'>Rails API demonstrating<br />PostgreSQL primary/replica<br />streaming replication with<br />PgCat as connection pooler</div>"]
    style 2 fill:#ffffff,stroke:#444444,color:#444444

    1-. "<div>sends HTTP requests to</div><div style='font-size: 70%'>[HTTP :80]</div>" .->2
  end
```

### Containers

```mermaid
graph LR
  linkStyle default fill:#ffffff

  subgraph diagram ["Container View: Replication API"]
    style diagram fill:#ffffff,stroke:#ffffff

    1["<div style='font-weight: bold'>Developer</div><div style='font-size: 70%; margin-top: 0px'>[Person]</div><div style='font-size: 80%; margin-top:10px'>Interacts with the API<br />locally or via the load<br />balancer</div>"]
    style 1 fill:#ffffff,stroke:#444444,color:#444444

    subgraph 2 ["Replication API"]
      style 2 fill:#ffffff,stroke:#444444,color:#444444

      3["<div style='font-weight: bold'>ALB</div><div style='font-size: 70%; margin-top: 0px'>[Container: AWS Application Load Balancer]</div><div style='font-size: 80%; margin-top:10px'>Internet-facing Application<br />Load Balancer. Routes HTTP<br />traffic to ECS tasks.</div>"]
      style 3 fill:#ffffff,stroke:#444444,color:#444444
      4["<div style='font-weight: bold'>Rails API</div><div style='font-size: 70%; margin-top: 0px'>[Container: Ruby on Rails 7 / Ruby 3]</div><div style='font-size: 80%; margin-top:10px'>Handles HTTP requests.<br />Connects to PgCat on<br />localhost:6432 for all<br />database operations.</div>"]
      style 4 fill:#ffffff,stroke:#444444,color:#444444
      5["<div style='font-weight: bold'>PgCat</div><div style='font-size: 70%; margin-top: 0px'>[Container: PgCat]</div><div style='font-size: 80%; margin-top:10px'>Connection pooler with query<br />parser. Routes SELECTs to<br />replica and writes to<br />primary. Pool size: 20.</div>"]
      style 5 fill:#ffffff,stroke:#444444,color:#444444
      6["<div style='font-weight: bold'>RDS Primary</div><div style='font-size: 70%; margin-top: 0px'>[Container: PostgreSQL 16 on AWS RDS db.t3.micro]</div><div style='font-size: 80%; margin-top:10px'>PostgreSQL 16 primary<br />instance. Handles all write<br />operations. Streams WAL to<br />replica.</div>"]
      style 6 fill:#ffffff,stroke:#444444,color:#444444
      7["<div style='font-weight: bold'>RDS Replica</div><div style='font-size: 70%; margin-top: 0px'>[Container: PostgreSQL 16 on AWS RDS db.t3.micro]</div><div style='font-size: 80%; margin-top:10px'>PostgreSQL 16 read replica.<br />Handles read queries routed<br />by PgCat. Read-only.</div>"]
      style 7 fill:#ffffff,stroke:#444444,color:#444444
      8["<div style='font-weight: bold'>ECR</div><div style='font-size: 70%; margin-top: 0px'>[Container: AWS Elastic Container Registry]</div><div style='font-size: 80%; margin-top:10px'>Container image registry.<br />Stores railsapi images tagged<br />with commit SHA and latest.</div>"]
      style 8 fill:#ffffff,stroke:#444444,color:#444444
      9["<div style='font-weight: bold'>GitHub Actions</div><div style='font-size: 70%; margin-top: 0px'>[Container: GitHub Actions / OIDC]</div><div style='font-size: 80%; margin-top:10px'>CI/CD pipeline. Builds and<br />pushes Docker image, updates<br />ECS task definition, runs<br />db:migrate.</div>"]
      style 9 fill:#ffffff,stroke:#444444,color:#444444
    end

    1-. "<div>sends HTTP requests to</div><div style='font-size: 70%'>[HTTP :80]</div>" .->3
    1-. "<div>uses locally via</div><div style='font-size: 70%'>[HTTP :3003 (Docker Compose)]</div>" .->4
    3-. "<div>forwards requests to</div><div style='font-size: 70%'>[HTTP :3000]</div>" .->4
    4-. "<div>queries via</div><div style='font-size: 70%'>[PostgreSQL :6432 (localhost in ECS task)]</div>" .->5
    5-. "<div>routes writes to</div><div style='font-size: 70%'>[PostgreSQL :5432]</div>" .->6
    5-. "<div>routes reads to</div><div style='font-size: 70%'>[PostgreSQL :5432]</div>" .->7
    6-. "<div>replicates WAL to</div><div style='font-size: 70%'>[PostgreSQL streaming replication]</div>" .->7
    9-. "<div>pushes Docker image to</div><div style='font-size: 70%'>[docker push]</div>" .->8
    9-. "<div>deploys via ECS task<br />definition update +<br />db:migrate</div><div style='font-size: 70%'>[AWS ECS API]</div>" .->4
  end
```

- **primarydb** — PostgreSQL primary with WAL-level logical replication and a physical replication slot (`replication_api_slot`)
- **replicadb** — PostgreSQL read-only replica cloned via `pg_basebackup`
- **pgcat** — Connection pooler with query parser enabled; routes `SELECT` to the replica and writes to the primary
- **railsapi** — Rails API pointing to PgCat via `DATABASE_URL`

---

## Setup

### 1. Copy the environment file

```bash
cp .env.sample .env
cp docker-compose.yml.sample docker-compose.yml
cp config/database.yml.sample config/database.yml
```

### 2. Start all services

```bash
docker compose up --build
```

On first boot the replica container will:

1. Wait for primarydb to be healthy
2. Confirm the replication slot exists
3. Run `pg_basebackup` to clone the primary
4. Start PostgreSQL in standby (read-only) mode

### 3. Create and migrate the database

Once all containers are running:

```bash
docker compose exec railsapi bin/rails db:create db:migrate
```

---

## Monitoring Replication

### Watch primary logs (writes + WAL activity)

```bash
docker compose logs -f primarydb
```

Look for lines like:

```
LOG:  starting logical decoding for slot "replication_api_slot"
LOG:  INSERT INTO "users" ...
```

### Watch replica logs (reads routed by PgCat)

```bash
docker compose logs -f replicadb
```

Look for lines like:

```
LOG:  started streaming WAL from primary at ...
LOG:  SELECT "users".* FROM "users" ...
```

### Confirm streaming replication is active (from primary)

```bash
docker compose exec primarydb psql -U postgres -c \
  "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn \
   FROM pg_stat_replication;"
```

A row with `state = streaming` confirms the replica is in sync.

### Check the replication slot

```bash
docker compose exec primarydb psql -U postgres -c \
  "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;"
```

`active = t` means the replica is connected and consuming WAL.

---

## Testing Read/Write Splitting

PgCat routes queries based on the SQL verb (`query_parser_read_write_splitting = true`). To observe the split:

### 1. Open a Rails console

```bash
docker compose exec railsapi bin/rails console
```

### 2. Trigger a write (routed to primary)

```ruby
User.create!(first_name: "Alice")
```

You will see the `INSERT` logged in `docker compose logs -f primarydb`.

### 3. Trigger a read (routed to replica)

```ruby
User.all.to_a
```

You will see the `SELECT` logged in `docker compose logs -f replicadb`.

### 4. Verify replication lag

```bash
docker compose exec primarydb psql -U postgres -c \
  "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag \
   FROM pg_stat_replication LIMIT 1;"
```

A near-zero lag confirms data written to the primary has been replicated.

---

## Local Deployment (Docker Compose)

```mermaid
graph LR
  linkStyle default fill:#ffffff

  subgraph diagram ["Deployment View: Replication API - Local (Docker Compose)"]
    style diagram fill:#ffffff,stroke:#ffffff

    subgraph 48 ["Developer Machine"]
      style 48 fill:#ffffff,stroke:#444444,color:#444444

      subgraph 49 ["Docker Network"]
        style 49 fill:#ffffff,stroke:#444444,color:#444444

        subgraph 50 ["railsapi container"]
          style 50 fill:#ffffff,stroke:#444444,color:#444444

          51["<div style='font-weight: bold'>Rails API</div><div style='font-size: 70%; margin-top: 0px'>[Container: Ruby on Rails 7 / Ruby 3]</div><div style='font-size: 80%; margin-top:10px'>Handles HTTP requests.<br />Connects to PgCat on<br />localhost:6432 for all<br />database operations.</div>"]
          style 51 fill:#ffffff,stroke:#444444,color:#444444
        end

        subgraph 52 ["pgcat container"]
          style 52 fill:#ffffff,stroke:#444444,color:#444444

          53["<div style='font-weight: bold'>PgCat</div><div style='font-size: 70%; margin-top: 0px'>[Container: PgCat]</div><div style='font-size: 80%; margin-top:10px'>Connection pooler with query<br />parser. Routes SELECTs to<br />replica and writes to<br />primary. Pool size: 20.</div>"]
          style 53 fill:#ffffff,stroke:#444444,color:#444444
        end

        subgraph 55 ["primarydb container"]
          style 55 fill:#ffffff,stroke:#444444,color:#444444

          56["<div style='font-weight: bold'>RDS Primary</div><div style='font-size: 70%; margin-top: 0px'>[Container: PostgreSQL 16 on AWS RDS db.t3.micro]</div><div style='font-size: 80%; margin-top:10px'>PostgreSQL 16 primary<br />instance. Handles all write<br />operations. Streams WAL to<br />replica.</div>"]
          style 56 fill:#ffffff,stroke:#444444,color:#444444
        end

        subgraph 58 ["replicadb container"]
          style 58 fill:#ffffff,stroke:#444444,color:#444444

          59["<div style='font-weight: bold'>RDS Replica</div><div style='font-size: 70%; margin-top: 0px'>[Container: PostgreSQL 16 on AWS RDS db.t3.micro]</div><div style='font-size: 80%; margin-top:10px'>PostgreSQL 16 read replica.<br />Handles read queries routed<br />by PgCat. Read-only.</div>"]
          style 59 fill:#ffffff,stroke:#444444,color:#444444
        end
      end
    end

    51-. "<div>queries via</div><div style='font-size: 70%'>[PostgreSQL :6432 (localhost in ECS task)]</div>" .->53
    53-. "<div>routes writes to</div><div style='font-size: 70%'>[PostgreSQL :5432]</div>" .->56
    53-. "<div>routes reads to</div><div style='font-size: 70%'>[PostgreSQL :5432]</div>" .->59
    56-. "<div>replicates WAL to</div><div style='font-size: 70%'>[PostgreSQL streaming replication]</div>" .->59
  end
```

---

## Ports

| Service   | Host port | Container port |
|-----------|-----------|----------------|
| primarydb | 54321     | 5432           |
| replicadb | 54322     | 5432           |
| pgcat     | 6432      | 6432           |
| railsapi  | 3003      | 3000           |

---

## Teardown

```bash
# Stop containers, keep volumes
docker compose down

# Stop and remove volumes (full reset)
docker compose down -v
```

---

## AWS ECS Architecture

The application can be deployed to AWS ECS using Terraform. The architecture uses the **sidecar pattern** — `railsapi` and `pgcat` run in the same ECS task and communicate over `localhost`. PgCat routes queries to the appropriate RDS instance automatically.

```mermaid
graph LR
  linkStyle default fill:#ffffff

  subgraph diagram ["Deployment View: Replication API - AWS (us-east-1)"]
    style diagram fill:#ffffff,stroke:#ffffff

    subgraph 20 ["AWS"]
      style 20 fill:#ffffff,stroke:#444444,color:#444444

      subgraph 21 ["us-east-1"]
        style 21 fill:#ffffff,stroke:#444444,color:#444444

        subgraph 22 ["VPC"]
          style 22 fill:#ffffff,stroke:#444444,color:#444444

          subgraph 23 ["ALB Security Group"]
            style 23 fill:#ffffff,stroke:#444444,color:#444444

            24["<div style='font-weight: bold'>ALB</div><div style='font-size: 70%; margin-top: 0px'>[Container: AWS Application Load Balancer]</div><div style='font-size: 80%; margin-top:10px'>Internet-facing Application<br />Load Balancer. Routes HTTP<br />traffic to ECS tasks.</div>"]
            style 24 fill:#ffffff,stroke:#444444,color:#444444
          end

          subgraph 25 ["ECS Cluster"]
            style 25 fill:#ffffff,stroke:#444444,color:#444444

            subgraph 26 ["ECS Service"]
              style 26 fill:#ffffff,stroke:#444444,color:#444444

              subgraph 27 ["ECS Task"]
                style 27 fill:#ffffff,stroke:#444444,color:#444444

                subgraph 28 ["ECS Security Group"]
                  style 28 fill:#ffffff,stroke:#444444,color:#444444

                  29["<div style='font-weight: bold'>Rails API</div><div style='font-size: 70%; margin-top: 0px'>[Container: Ruby on Rails 7 / Ruby 3]</div><div style='font-size: 80%; margin-top:10px'>Handles HTTP requests.<br />Connects to PgCat on<br />localhost:6432 for all<br />database operations.</div>"]
                  style 29 fill:#ffffff,stroke:#444444,color:#444444
                  31["<div style='font-weight: bold'>PgCat</div><div style='font-size: 70%; margin-top: 0px'>[Container: PgCat]</div><div style='font-size: 80%; margin-top:10px'>Connection pooler with query<br />parser. Routes SELECTs to<br />replica and writes to<br />primary. Pool size: 20.</div>"]
                  style 31 fill:#ffffff,stroke:#444444,color:#444444
                end
              end
            end
          end

          subgraph 33 ["RDS Security Group"]
            style 33 fill:#ffffff,stroke:#444444,color:#444444

            subgraph 34 ["RDS Primary Instance"]
              style 34 fill:#ffffff,stroke:#444444,color:#444444

              35["<div style='font-weight: bold'>RDS Primary</div><div style='font-size: 70%; margin-top: 0px'>[Container: PostgreSQL 16 on AWS RDS db.t3.micro]</div><div style='font-size: 80%; margin-top:10px'>PostgreSQL 16 primary<br />instance. Handles all write<br />operations. Streams WAL to<br />replica.</div>"]
              style 35 fill:#ffffff,stroke:#444444,color:#444444
            end

            subgraph 37 ["RDS Replica Instance"]
              style 37 fill:#ffffff,stroke:#444444,color:#444444

              38["<div style='font-weight: bold'>RDS Replica</div><div style='font-size: 70%; margin-top: 0px'>[Container: PostgreSQL 16 on AWS RDS db.t3.micro]</div><div style='font-size: 80%; margin-top:10px'>PostgreSQL 16 read replica.<br />Handles read queries routed<br />by PgCat. Read-only.</div>"]
              style 38 fill:#ffffff,stroke:#444444,color:#444444
            end
          end
        end

        subgraph 41 ["ECR Repository"]
          style 41 fill:#ffffff,stroke:#444444,color:#444444

          42["<div style='font-weight: bold'>ECR</div><div style='font-size: 70%; margin-top: 0px'>[Container: AWS Elastic Container Registry]</div><div style='font-size: 80%; margin-top:10px'>Container image registry.<br />Stores railsapi images tagged<br />with commit SHA and latest.</div>"]
          style 42 fill:#ffffff,stroke:#444444,color:#444444
        end
      end
    end

    subgraph 43 ["GitHub"]
      style 43 fill:#ffffff,stroke:#444444,color:#444444

      subgraph 44 ["GitHub Actions Runner"]
        style 44 fill:#ffffff,stroke:#444444,color:#444444

        45["<div style='font-weight: bold'>GitHub Actions</div><div style='font-size: 70%; margin-top: 0px'>[Container: GitHub Actions / OIDC]</div><div style='font-size: 80%; margin-top:10px'>CI/CD pipeline. Builds and<br />pushes Docker image, updates<br />ECS task definition, runs<br />db:migrate.</div>"]
        style 45 fill:#ffffff,stroke:#444444,color:#444444
      end
    end

    24-. "<div>forwards requests to</div><div style='font-size: 70%'>[HTTP :3000]</div>" .->29
    29-. "<div>queries via</div><div style='font-size: 70%'>[PostgreSQL :6432 (localhost in ECS task)]</div>" .->31
    31-. "<div>routes writes to</div><div style='font-size: 70%'>[PostgreSQL :5432]</div>" .->35
    31-. "<div>routes reads to</div><div style='font-size: 70%'>[PostgreSQL :5432]</div>" .->38
    35-. "<div>replicates WAL to</div><div style='font-size: 70%'>[PostgreSQL streaming replication]</div>" .->38
    45-. "<div>deploys via ECS task<br />definition update +<br />db:migrate</div><div style='font-size: 70%'>[AWS ECS API]</div>" .->29
    45-. "<div>pushes Docker image to</div><div style='font-size: 70%'>[docker push]</div>" .->42
  end
```

| Component | Role |
|-----------|------|
| **ALB** | Internet-facing load balancer; distributes traffic across ECS tasks |
| **ECS Service** | Maintains desired number of running tasks; auto-restarts on failure |
| **railsapi** | Your Rails app, connects to PgCat on `localhost:6432` |
| **pgcat** | Sidecar container; routes SELECTs to replica, writes to primary |
| **RDS Primary** | Managed PostgreSQL; handles all write operations |
| **RDS Replica** | Read replica; automatically replicates from primary via WAL streaming |

---

## Deploying to AWS ECS

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

### 1. Provision infrastructure with Terraform

```bash
cd terraform

# Create your variables file (NEVER commit this!)
cp terraform.tfvars.sample terraform.tfvars
# Edit terraform.tfvars and set your db_password

# Download providers
terraform init

# Preview what will be created
terraform plan

# Create everything (type "yes" to confirm)
terraform apply
```

Note the outputs after apply completes — you will need `github_actions_role_arn` and `ecr_repository_url`.

### 2. Configure GitHub Actions

1. Create a `production` branch in your repository
2. Go to **Settings > Secrets and variables > Actions > Variables**
3. Add a variable `AWS_ROLE_ARN` with the value from the Terraform output `github_actions_role_arn`
4. Every merged PR to `production` will now trigger an automatic deployment, including `db:create` and `db:migrate` before the service is updated

### 3. Tear down infrastructure

```bash
cd terraform

# Preview what will be destroyed
terraform plan -destroy

# Destroy everything (type "yes" to confirm)
terraform destroy
```

### Cost estimate

| Resource | Monthly Cost |
|---|---|
| RDS db.t3.micro x2 | ~$0 (free tier 12 months, ~$30 after) |
| ECS Fargate (0.25 vCPU, 0.5 GB) x2 | ~$15 |
| ALB | ~$16 + data transfer |
| ECR | ~$0 (first 500 MB free) |
| CloudWatch Logs | ~$0 (minimal) |
| **Total** | **~$31–61/month** |

To minimize costs while learning, set `desired_count = 1` in your Terraform variables and run `terraform destroy` when not using it.
