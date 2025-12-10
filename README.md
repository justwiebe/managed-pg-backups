# ManagedPgBackups

A Ruby gem for managing PostgreSQL incremental backups using `pg_basebackup` and `pg_combinebackup`. Designed to replace managed database backup solutions like Heroku Postgres with self-hosted backup infrastructure.

## Features

- 🔄 **Incremental Backups**: Uses PostgreSQL's native incremental backup feature to minimize storage and backup time
- ☁️ **Multiple Storage Backends**: Supports local filesystem and Amazon S3
- 📦 **WAL Archiving**: Automatic Write-Ahead Log archiving for point-in-time recovery
- ⏰ **Automated Scheduling**: Built-in scheduler for regular full and incremental backups
- 🎯 **Point-in-Time Recovery (PITR)**: Restore your database to any point in time
- 🧹 **Retention Management**: Automatic cleanup of old backup chains
- 🛠️ **Rake Tasks**: Easy-to-use Rake tasks for backup and restore operations
- 🔌 **Zero-Config Philosophy**: Works with minimal configuration

## Requirements

- Ruby >= 3.0
- PostgreSQL >= 17 (for incremental backup support)
- Rails application (optional, but recommended)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'managed_pg_backups'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install managed_pg_backups
```

## Quick Start

### 1. Configure the Gem

Create an initializer file `config/initializers/managed_pg_backups.rb`:

```ruby
ManagedPgBackups.configure do |config|
  # Database connection (uses ENV vars by default)
  config.database_host = ENV.fetch("PGHOST", "localhost")
  config.database_port = ENV.fetch("PGPORT", "5432").to_i
  config.database_name = ENV.fetch("PGDATABASE", "myapp_production")
  config.database_user = ENV.fetch("PGUSER", "postgres")
  config.database_password = ENV["PGPASSWORD"]

  # Storage configuration
  config.storage_type = :s3  # or :local
  
  # For S3 storage:
  config.s3_bucket = "my-postgres-backups"
  config.s3_region = "us-east-1"
  config.s3_access_key_id = ENV["AWS_ACCESS_KEY_ID"]
  config.s3_secret_access_key = ENV["AWS_SECRET_ACCESS_KEY"]

  # For local storage:
  # config.storage_type = :local
  # config.storage_path = "/var/backups/postgres"

  # Backup schedule (cron format)
  config.full_backup_schedule = "0 2 * * 0"        # Weekly on Sunday at 2am
  config.incremental_backup_schedule = "0 2 * * *" # Daily at 2am

  # Retention policy
  config.retention_count = 4  # Keep 4 full backup chains
end
```

### 2. Configure PostgreSQL for WAL Archiving

Get the archive command:

```bash
bundle exec rake pg_backups:archive_command
```

Add the output to your `postgresql.conf`:

```
wal_level = replica
archive_mode = on
archive_command = '/path/to/archive_wal.sh %p %f'
```

Restart PostgreSQL to apply changes.

### 3. Run Your First Backup

```bash
# Create a full backup
bundle exec rake pg_backups:full

# Create an incremental backup
bundle exec rake pg_backups:incremental

# List all backups
bundle exec rake pg_backups:list
```

## Usage

### Rake Tasks

```bash
# Backup operations
rake pg_backups:full              # Run a full backup
rake pg_backups:incremental       # Run an incremental backup
rake pg_backups:list              # List all backup chains
rake pg_backups:cleanup           # Clean up old backups

# Restore operations
rake pg_backups:restore[/path/to/restore]  # Restore latest backup

# Scheduler
rake pg_backups:scheduler         # Start background scheduler

# Configuration helpers
rake pg_backups:archive_command   # Show WAL archive command
```

### Programmatic Usage

#### Taking Backups

```ruby
# Full backup
result = ManagedPgBackups.backup_manager.perform_full_backup
# => { success: true, backup_dir: "backups/full_20231209_120000", manifest: "..." }

# Incremental backup
result = ManagedPgBackups.backup_manager.perform_incremental_backup
# => { success: true, backup_dir: "backups/incremental_20231209_140000", manifest: "..." }
```

#### Restoring Backups

```ruby
# Restore latest backup
result = ManagedPgBackups.restore_manager.restore(
  target_dir: "/var/lib/postgresql/data"
)

# Restore specific chain
result = ManagedPgBackups.restore_manager.restore(
  chain_id: "abc-123-def",
  target_dir: "/var/lib/postgresql/data"
)

# Point-in-time recovery
result = ManagedPgBackups.restore_manager.restore(
  target_time: Time.parse("2023-12-09 12:00:00 UTC"),
  target_dir: "/var/lib/postgresql/data"
)
```

#### Managing Backup Chains

```ruby
# List all chains
chains = ManagedPgBackups.backup_chain.all_chains

# Get latest chain
latest = ManagedPgBackups.backup_chain.latest_chain

# Delete old chains
ManagedPgBackups.backup_chain.cleanup_old_chains
```

### Running the Scheduler

#### As a Background Process

In your Rails application, add to `config/initializers/managed_pg_backups.rb`:

```ruby
if defined?(Rails) && Rails.env.production?
  Thread.new do
    ManagedPgBackups.scheduler.start
  end
end
```

#### Using a Process Manager (Recommended)

With Foreman (`Procfile`):

```
backups: bundle exec rake pg_backups:scheduler
```

With systemd (`/etc/systemd/system/pg-backups.service`):

```ini
[Unit]
Description=PostgreSQL Backup Scheduler
After=network.target

[Service]
Type=simple
User=postgres
WorkingDirectory=/path/to/app
ExecStart=/path/to/bundle exec rake pg_backups:scheduler
Restart=always

[Install]
WantedBy=multi-user.target
```

## Architecture

### Backup Flow

```
1. Full Backup (pg_basebackup)
   └─> Upload to storage
   └─> Save manifest for future incrementals

2. Incremental Backup (pg_basebackup --incremental)
   └─> Reference previous manifest
   └─> Upload only changed blocks
   └─> Save new manifest

3. Repeat incrementals until next full backup
```

### Restore Flow

```
1. Download full backup + all incrementals
2. Combine using pg_combinebackup
3. Configure recovery settings
4. Replay WAL logs for PITR (if needed)
5. Start PostgreSQL in recovery mode
```

## Docker Usage

If running PostgreSQL in Docker:

```ruby
# In your configuration
config.database_host = "postgres"  # Docker service name
config.storage_path = "/backups"   # Mounted volume
```

Example `docker-compose.yml`:

```yaml
version: '3.8'
services:
  postgres:
    image: postgres:17
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backups:/backups
    environment:
      POSTGRES_PASSWORD: password

  app:
    build: .
    depends_on:
      - postgres
    volumes:
      - ./backups:/backups
    environment:
      PGHOST: postgres
      PGDATABASE: myapp_production
      PGUSER: postgres
      PGPASSWORD: password
```

## Configuration Reference

| Option | Default | Description |
|--------|---------|-------------|
| `database_host` | `localhost` | PostgreSQL host |
| `database_port` | `5432` | PostgreSQL port |
| `database_name` | `postgres` | Database name |
| `database_user` | `postgres` | Database user |
| `database_password` | `nil` | Database password |
| `storage_type` | `:local` | `:local` or `:s3` |
| `storage_path` | `./backups` | Local storage path |
| `s3_bucket` | `nil` | S3 bucket name |
| `s3_region` | `us-east-1` | S3 region |
| `full_backup_schedule` | `0 2 * * 0` | Cron schedule for full backups |
| `incremental_backup_schedule` | `0 2 * * *` | Cron schedule for incremental backups |
| `retention_count` | `4` | Number of backup chains to keep |

## Troubleshooting

### Backup Fails

- Ensure PostgreSQL user has replication permissions
- Check that WAL archiving is properly configured
- Verify storage credentials and permissions

### Restore Fails

- Ensure all backups in the chain are available
- Check that `pg_combinebackup` is in PATH
- Verify WAL archive is accessible

### Incremental Backup Not Working

- Requires PostgreSQL 17+
- Ensure WAL summarizer is running
- Check that manifest from previous backup exists

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/justwiebe/managed-pg-backups.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
