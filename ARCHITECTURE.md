# ManagedPgBackups Architecture

## Overview

This gem provides a complete solution for managing PostgreSQL incremental backups using native PostgreSQL tools (`pg_basebackup` and `pg_combinebackup`). It's designed to work seamlessly in Rails applications, Docker environments, and standalone Ruby applications.

## Core Components

### 1. Configuration (`lib/managed_pg_backups/configuration.rb`)
- Central configuration management
- Database connection settings
- Storage backend configuration (local/S3)
- Backup schedules (cron format)
- Retention policies
- Environment variable support

### 2. Storage Layer (`lib/managed_pg_backups/storage/`)
- **Base** (`base.rb`): Abstract interface for storage backends
- **Local** (`local.rb`): Filesystem-based storage implementation
- **S3** (`s3.rb`): Amazon S3 storage implementation

**Storage Operations:**
- `upload(local_path, remote_path)` - Upload files/directories
- `download(remote_path, local_path)` - Download files/directories
- `list(remote_path)` - List files in storage
- `delete(remote_path)` - Delete files/directories
- `exists?(remote_path)` - Check file existence

### 3. WAL Archiver (`lib/managed_pg_backups/wal_archiver.rb`)
Manages Write-Ahead Log archiving for PostgreSQL.

**Key Functions:**
- Generates `archive_command` for postgresql.conf
- Archives WAL segments to storage
- Generates `restore_command` for recovery
- Restores WAL segments during recovery
- Cleans up old WAL files based on backup retention

**WAL Archive Flow:**
```
PostgreSQL → archive_command → WAL Archiver → Storage (S3/Local)
```

### 4. Backup Chain Tracker (`lib/managed_pg_backups/backup_chain.rb`)
Tracks relationships between full and incremental backups in YAML format.

**Metadata Structure:**
```yaml
chains:
  - chain_id: "uuid-1"
    type: "full"
    timestamp: "2023-12-09T12:00:00Z"
    backup_path: "backups/full_20231209_120000"
    manifest_path: "manifests/backup_manifest_20231209_120000"
    incrementals:
      - backup_id: "uuid-2"
        timestamp: "2023-12-10T12:00:00Z"
        backup_path: "backups/incremental_20231210_120000"
        manifest_path: "manifests/backup_manifest_20231210_120000"
```

**Key Functions:**
- Register full backups
- Register incremental backups
- Track backup dependencies
- Get restore chains (including PITR support)
- Cleanup old chains based on retention

### 5. Backup Manager (`lib/managed_pg_backups/backup_manager.rb`)
Executes `pg_basebackup` commands for full and incremental backups.

**Full Backup Flow:**
```
1. Create temp directory
2. Run: pg_basebackup -D <dir> --manifest-path=<manifest>
3. Upload backup directory to storage
4. Upload manifest to storage
5. Register in backup chain
6. Cleanup temp files
```

**Incremental Backup Flow:**
```
1. Download parent manifest from storage
2. Create temp directory
3. Run: pg_basebackup -D <dir> --incremental=<parent_manifest>
4. Upload incremental backup to storage
5. Upload new manifest to storage
6. Register in backup chain as child
7. Cleanup temp files
```

### 6. Restore Manager (`lib/managed_pg_backups/restore_manager.rb`)
Combines incremental backups and configures PostgreSQL recovery.

**Restore Flow:**
```
1. Identify required backups (full + incrementals up to target)
2. Download all required backups from storage
3. Run: pg_combinebackup <full> <inc1> <inc2> ... -o <output>
4. Create recovery.signal file
5. Configure restore_command in postgresql.auto.conf
6. Set recovery_target_time if PITR requested
7. Return instructions for PostgreSQL restart
```

**PITR Support:**
- Downloads backups up to target time
- Configures recovery_target_time
- PostgreSQL replays WAL logs to exact timestamp

### 7. Scheduler (`lib/managed_pg_backups/scheduler.rb`)
Automates backup execution using Rufus Scheduler.

**Schedules:**
- Full backups (configurable, default: weekly)
- Incremental backups (configurable, default: daily)
- Cleanup operations (daily at 3 AM)

**Smart Scheduling:**
- If no full backup exists, creates one instead of incremental
- Handles errors gracefully
- Logs all operations

### 8. Railtie (`lib/managed_pg_backups/railtie.rb`)
Rails integration for automatic Rake task loading.

## Data Flow

### Backup Creation
```
Scheduler → Backup Manager → pg_basebackup → Storage → Backup Chain (metadata)
                                    ↓
                          WAL Archiver → Storage
```

### Restore Operation
```
User Request → Restore Manager → Storage (download) → pg_combinebackup → Output Dir
                                                    ↓
                                          WAL Archiver (restore_command)
                                                    ↓
                                          PostgreSQL Recovery
```

## Storage Organization

```
storage_root/
├── backups/
│   ├── full_20231209_120000/
│   │   └── [PostgreSQL data files]
│   ├── incremental_20231210_120000/
│   │   └── [Changed blocks only]
│   └── incremental_20231211_120000/
│       └── [Changed blocks only]
├── manifests/
│   ├── backup_manifest_20231209_120000
│   ├── backup_manifest_20231210_120000
│   └── backup_manifest_20231211_120000
├── wal_archive/
│   ├── 000000010000000000000001
│   ├── 000000010000000000000002
│   └── ...
├── scripts/
│   ├── archive_wal.sh
│   └── restore_wal.sh
└── backup_metadata.yml
```

## Key Design Decisions

### 1. YAML for Metadata
- No database dependency
- Portable across environments
- Easy to backup with the actual backups
- Human-readable for troubleshooting

### 2. Shell Scripts for WAL Operations
- Required by PostgreSQL's archive_command/restore_command
- Bridges Ruby gem with PostgreSQL processes
- Allows gem to run independently of PostgreSQL process

### 3. Storage Abstraction
- Easy to add new storage backends
- Consistent interface for all operations
- Supports both cloud and on-premises deployments

### 4. Incremental Chain Tracking
- Ensures all dependencies are maintained
- Prevents accidental deletion of required backups
- Supports multiple parallel backup chains (for testing)

### 5. Scheduler Independence
- Can run as background thread in Rails
- Can run as separate process (systemd, Docker, etc.)
- Rake tasks available for manual/cron execution

## Security Considerations

1. **Database Credentials**: Use environment variables
2. **S3 Credentials**: Use IAM roles when possible
3. **WAL Files**: Contain all database changes - secure storage required
4. **Backup Files**: Full database dumps - encrypt at rest
5. **Restore Operations**: Verify backup integrity before restore

## Performance Characteristics

### Full Backup
- Time: Proportional to database size
- Space: ~100% of database size
- Network: Full database transfer

### Incremental Backup
- Time: Proportional to changed data
- Space: Only changed blocks (~5-20% typical)
- Network: Only changed blocks transfer

### Restore
- Time: pg_combinebackup + WAL replay
- Space: Full database size for output
- Network: Download full + all incrementals

## Future Enhancements

1. Compression support for backups
2. Encryption at rest
3. Backup verification/testing
4. Multi-database support
5. Backup statistics and monitoring
6. Parallel backup/restore operations
7. Azure Blob Storage support
8. GCS (Google Cloud Storage) support
