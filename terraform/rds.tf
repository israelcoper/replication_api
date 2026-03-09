# =============================================================================
# RDS — PostgreSQL Primary + Read Replica
# =============================================================================
# RDS (Relational Database Service) is a managed PostgreSQL service.
# AWS handles backups, patching, and failover — you just use it.
#
# We create:
#   1. A primary instance (handles reads AND writes)
#   2. A read replica (handles reads only, replicates from primary via WAL)
#
# This replaces your local primarydb and replicadb containers.
# =============================================================================

# A "subnet group" tells RDS which subnets (and therefore which AZs)
# the database can be placed in. Using multiple AZs = fault tolerance.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# --- Primary RDS Instance ---
# This is your main database. All writes go here.
resource "aws_db_instance" "primary" {
  identifier = "${var.project_name}-primary"

  # Engine settings
  engine         = "postgres"
  engine_version = "16.4"                 # Match your local PostgreSQL 16.x
  instance_class = "db.t3.micro"          # Smallest instance — FREE TIER eligible!

  # Storage
  allocated_storage     = 20              # 20 GB — minimum for free tier
  max_allocated_storage = 50              # Auto-scale up to 50 GB if needed
  storage_type          = "gp3"           # General purpose SSD (cheapest SSD)

  # Database credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false          # NEVER expose DB to internet!

  # Replication settings (needed for the read replica)
  backup_retention_period = 7             # Keep 7 days of automated backups
  # (read replicas require backups to be enabled, retention > 0)

  # Cost savings
  skip_final_snapshot       = true        # Don't create a snapshot when destroying
                                          # (set to false in real production!)
  deletion_protection       = false       # Allow Terraform to delete this
                                          # (set to true in real production!)
  multi_az                  = false       # Single AZ to save cost
                                          # (set to true in real production for HA!)

  # Performance
  performance_insights_enabled = false    # Disable to save cost

  tags = {
    Name = "${var.project_name}-primary"
    Role = "primary"
  }
}

# --- Read Replica ---
# This automatically replicates data from the primary using PostgreSQL
# streaming replication (WAL). It's read-only — same as your local replicadb.
resource "aws_db_instance" "replica" {
  identifier = "${var.project_name}-replica"

  # IMPORTANT: replicate_source_db links this to the primary.
  # AWS handles all the replication setup automatically!
  replicate_source_db = aws_db_instance.primary.identifier

  # Must match the primary's engine
  instance_class = "db.t3.micro"          # Same as primary — free tier eligible

  # Networking (inherits subnet group from primary via replicate_source_db)
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Replica-specific settings
  skip_final_snapshot = true
  # Note: You cannot set backup_retention_period, db_name, username, or password
  # on a read replica — they inherit from the primary.

  tags = {
    Name = "${var.project_name}-replica"
    Role = "replica"
  }
}
