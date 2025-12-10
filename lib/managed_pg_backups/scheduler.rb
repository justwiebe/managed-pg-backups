# frozen_string_literal: true

require "rufus-scheduler"

module ManagedPgBackups
  class Scheduler
    attr_reader :config, :backup_manager, :backup_chain, :scheduler

    def initialize(config, backup_manager, backup_chain)
      @config = config
      @backup_manager = backup_manager
      @backup_chain = backup_chain
      @scheduler = Rufus::Scheduler.new
    end

    def start
      schedule_full_backups
      schedule_incremental_backups
      schedule_cleanup

      puts "Backup scheduler started"
      puts "Full backups: #{config.full_backup_schedule}"
      puts "Incremental backups: #{config.incremental_backup_schedule}"
      
      scheduler.join
    end

    def stop
      scheduler.shutdown
      puts "Backup scheduler stopped"
    end

    def run_full_backup_now
      puts "Running full backup..."
      result = backup_manager.perform_full_backup
      puts "Full backup completed: #{result[:backup_dir]}"
      result
    rescue StandardError => e
      puts "Full backup failed: #{e.message}"
      raise
    end

    def run_incremental_backup_now
      puts "Running incremental backup..."
      result = backup_manager.perform_incremental_backup
      puts "Incremental backup completed: #{result[:backup_dir]}"
      result
    rescue StandardError => e
      puts "Incremental backup failed: #{e.message}"
      raise
    end

    def run_cleanup_now
      puts "Running cleanup..."
      backup_chain.cleanup_old_chains
      puts "Cleanup completed"
    rescue StandardError => e
      puts "Cleanup failed: #{e.message}"
      raise
    end

    private

    def schedule_full_backups
      scheduler.cron(config.full_backup_schedule) do
        run_full_backup_now
      end
    end

    def schedule_incremental_backups
      scheduler.cron(config.incremental_backup_schedule) do
        latest_chain = backup_chain.latest_chain
        
        if latest_chain.nil?
          puts "No full backup exists, running full backup instead..."
          run_full_backup_now
        else
          run_incremental_backup_now
        end
      end
    end

    def schedule_cleanup
      scheduler.cron("0 3 * * *") do
        run_cleanup_now
      end
    end
  end
end
