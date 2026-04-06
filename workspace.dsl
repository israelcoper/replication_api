workspace "Replication API" "Rails API with PostgreSQL primary/replica streaming replication via PgCat" {

  model {
    developer = person "Developer" "Interacts with the API locally or via the load balancer"

    replicationApiSystem = softwareSystem "Replication API" "Rails API demonstrating PostgreSQL primary/replica streaming replication with PgCat as connection pooler" {

      alb = container "ALB" "Internet-facing Application Load Balancer. Routes HTTP traffic to ECS tasks." "AWS Application Load Balancer" {
        tags "Infrastructure"
      }

      railsApi = container "Rails API" "Handles HTTP requests. Connects to PgCat on localhost:6432 for all database operations." "Ruby on Rails 7 / Ruby 3" {
        tags "Application"
      }

      pgcat = container "PgCat" "Connection pooler with query parser. Routes SELECTs to replica and writes to primary. Pool size: 20." "PgCat" {
        tags "Middleware"
      }

      rdsPrimary = container "RDS Primary" "PostgreSQL 16 primary instance. Handles all write operations. Streams WAL to replica." "PostgreSQL 16 on AWS RDS db.t3.micro" {
        tags "Database"
      }

      rdsReplica = container "RDS Replica" "PostgreSQL 16 read replica. Handles read queries routed by PgCat. Read-only." "PostgreSQL 16 on AWS RDS db.t3.micro" {
        tags "Database"
      }

      ecr = container "ECR" "Container image registry. Stores railsapi images tagged with commit SHA and latest." "AWS Elastic Container Registry" {
        tags "Infrastructure"
      }

      githubActions = container "GitHub Actions" "CI/CD pipeline. Builds and pushes Docker image, updates ECS task definition, runs db:migrate." "GitHub Actions / OIDC" {
        tags "CICD"
      }
    }

    # Relationships
    developer -> alb "sends HTTP requests to" "HTTP :80"
    developer -> railsApi "uses locally via" "HTTP :3003 (Docker Compose)"

    alb -> railsApi "forwards requests to" "HTTP :3000"

    railsApi -> pgcat "queries via" "PostgreSQL :6432 (localhost in ECS task)"

    pgcat -> rdsPrimary "routes writes to" "PostgreSQL :5432"
    pgcat -> rdsReplica "routes reads to" "PostgreSQL :5432"

    rdsPrimary -> rdsReplica "replicates WAL to" "PostgreSQL streaming replication"

    githubActions -> ecr "pushes Docker image to" "docker push"
    githubActions -> railsApi "deploys via ECS task definition update + db:migrate" "AWS ECS API"

    deploymentEnvironment "AWS (us-east-1)" {
      deploymentNode "AWS" "Amazon Web Services" "AWS" {
        tags "Infrastructure"

        deploymentNode "us-east-1" "US East (N. Virginia)" "AWS Region" {

          deploymentNode "VPC" "Default VPC" "AWS VPC" {

            deploymentNode "ALB Security Group" "Ingress: 0.0.0.0/0:80" "AWS Security Group" {
              containerInstance alb
            }

            deploymentNode "ECS Cluster" "replication-api-cluster" "AWS ECS Fargate" {
              deploymentNode "ECS Service" "1-4 tasks, auto-scaling on CPU 70%" "AWS ECS Service" {
                deploymentNode "ECS Task" "railsApi + pgcat sidecar (awsvpc networking)" "AWS Fargate Task" {
                  deploymentNode "ECS Security Group" "Ingress: ALB-only:3000" "AWS Security Group" {
                    containerInstance railsApi
                    containerInstance pgcat
                  }
                }
              }
            }

            deploymentNode "RDS Security Group" "Ingress: ECS-only:5432" "AWS Security Group" {
              deploymentNode "RDS Primary Instance" "replication-api-primary, db.t3.micro, 20GB" "AWS RDS PostgreSQL 16" {
                containerInstance rdsPrimary
              }
              deploymentNode "RDS Replica Instance" "replication-api-replica, db.t3.micro" "AWS RDS Read Replica" {
                containerInstance rdsReplica
              }
            }
          }

          deploymentNode "ECR Repository" "replication-api/railsapi, 10-image lifecycle policy" "AWS ECR" {
            containerInstance ecr
          }
        }
      }

      deploymentNode "GitHub" "GitHub.com" "GitHub" {
        deploymentNode "GitHub Actions Runner" "OIDC auth to AWS, triggers on push to production branch" "GitHub Actions" {
          containerInstance githubActions
        }
      }
    }

    deploymentEnvironment "Local (Docker Compose)" {
      deploymentNode "Developer Machine" "Local development environment" "macOS / Linux" {
        deploymentNode "Docker Network" "replication-net bridge network" "Docker Compose" {

          deploymentNode "railsapi container" "Host port 3003 → container port 3000" "Docker" {
            containerInstance railsApi
          }

          deploymentNode "pgcat container" "Host port 6432 → container port 6432" "Docker" {
            containerInstance pgcat
          }

          deploymentNode "primarydb container" "Host port 54321 → container port 5432" "Docker (postgres:16)" {
            containerInstance rdsPrimary
          }

          deploymentNode "replicadb container" "Host port 54322 → container port 5432. Cloned via pg_basebackup on first boot." "Docker (postgres:16)" {
            containerInstance rdsReplica
          }
        }
      }
    }
  }

  views {

    systemContext replicationApiSystem "SystemContext" "System context for the Replication API" {
      include *
      autoLayout lr
    }

    container replicationApiSystem "Containers" "Container view showing all components and their relationships" {
      include *
      autoLayout lr
    }

    deployment replicationApiSystem "AWS (us-east-1)" "AWSDeployment" "Production deployment on AWS ECS with RDS" {
      include *
      autoLayout lr
    }

    deployment replicationApiSystem "Local (Docker Compose)" "LocalDeployment" "Local development via Docker Compose" {
      include *
      autoLayout lr
    }

    styles {
      element "Person" {
        shape Person
        background #1168bd
        color #ffffff
      }
      element "Software System" {
        background #1168bd
        color #ffffff
      }
      element "Application" {
        background #1a6bbf
        color #ffffff
      }
      element "Middleware" {
        background #7b2d8b
        color #ffffff
      }
      element "Database" {
        shape Cylinder
        background #d47a00
        color #ffffff
      }
      element "Infrastructure" {
        background #6c757d
        color #ffffff
      }
      element "CICD" {
        background #2ea44f
        color #ffffff
      }
    }
  }

}
