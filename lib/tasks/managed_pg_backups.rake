# frozen_string_literal: true

require "managed_pg_backups"

namespace :pg_backups do
  desc "Run a full backup"
  task :full do
    puts "Starting full backup..."
    result = ManagedPgBackups.backup_manager.perform_full_backup
    puts "Full backup completed successfully!"
    puts "Backup directory: #{result[:backup_dir]}"
    puts "Manifest: #{result[:manifest]}"
  end

  desc "Run an incremental backup"
  task :incremental do
    puts "Starting incremental backup..."
    result = ManagedPgBackups.backup_manager.perform_incremental_backup
    puts "Incremental backup completed successfully!"
    puts "Backup directory: #{result[:backup_dir]}"
    puts "Manifest: #{result[:manifest]}"
  end

  desc "Restore from the latest backup"
  task :restore, [:target_dir] do |_t, args|
    target_dir = args[:target_dir]
    puts "Starting restore..."
    result = ManagedPgBackups.restore_manager.restore(target_dir: target_dir)
    puts "Restore completed successfully!"
    puts "Target directory: #{result[:target_dir]}"
    puts "Backups restored: #{result[:backups_restored]}"
  end

  desc "List all backup chains"
  task :list do
    chains = ManagedPgBackups.backup_chain.all_chains
    if chains.empty?
      puts "No backup chains found"
    else
      puts "\nBackup Chains:"
      chains.each do |chain|
        puts "Chain ID: #{chain['chain_id']}"
        puts "  Timestamp: #{chain['timestamp']}"
        puts "  Incrementals: #{chain['incrementals']&.size || 0}"
      end
    end
  end

  desc "Clean up old backup chains"
  task :cleanup do
    puts "Starting cleanup..."
    ManagedPgBackups.backup_chain.cleanup_old_chains
    puts "Cleanup completed!"
  end

  desc "Start the backup scheduler"
  task :scheduler do
    puts "Starting backup scheduler..."
    ManagedPgBackups.scheduler.start
  end

  desc "Show WAL archive command"
  task :archive_command do
    puts "\nAdd to postgresql.conf:"
    puts "archive_mode = on"
    puts "archive_command = '#{ManagedPgBackups.wal_archiver.archive_command}'"
  end
end
