# frozen_string_literal: true

require "open3"
require "fileutils"

module ManagedPgBackups
  class RestoreManager
    attr_reader :config, :storage, :backup_chain

    def initialize(config, storage, backup_chain)
      @config = config
      @storage = storage
      @backup_chain = backup_chain
    end

    def restore(chain_id: nil, target_time: nil, target_dir: nil)
      chain_id ||= backup_chain.latest_chain["chain_id"]
      raise RestoreError, "No backup chain found" unless chain_id

      restore_chain = backup_chain.get_restore_chain(chain_id, target_time: target_time)
      raise RestoreError, "No backups found for chain" unless restore_chain&.any?

      target_dir ||= config.storage_path + "/restored"
      FileUtils.mkdir_p(target_dir)

      download_and_combine_backups(restore_chain, target_dir)
      configure_recovery(target_dir, target_time)

      {
        success: true,
        target_dir: target_dir,
        chain_id: chain_id,
        backups_restored: restore_chain.size
      }
    end

    private

    def download_and_combine_backups(restore_chain, target_dir)
      temp_base = File.join(Dir.tmpdir, "pg_restore_#{Time.now.to_i}")
      FileUtils.mkdir_p(temp_base)

      begin
        full_backup = restore_chain.first
        full_backup_dir = File.join(temp_base, "full")
        
        puts "Downloading full backup..."
        storage.download(full_backup["backup_path"], full_backup_dir)

        if restore_chain.size == 1
          puts "No incrementals, using full backup directly..."
          FileUtils.cp_r(Dir.glob("#{full_backup_dir}/*"), target_dir)
        else
          incremental_dirs = []
          restore_chain[1..-1].each_with_index do |inc, idx|
            inc_dir = File.join(temp_base, "incremental_#{idx}")
            puts "Downloading incremental backup #{idx + 1}..."
            storage.download(inc["backup_path"], inc_dir)
            incremental_dirs << inc_dir
          end

          puts "Combining backups with pg_combinebackup..."
          combine_backups(full_backup_dir, incremental_dirs, target_dir)
        end
      ensure
        FileUtils.rm_rf(temp_base) if Dir.exist?(temp_base)
      end
    end

    def combine_backups(full_dir, incremental_dirs, output_dir)
      cmd = [
        "pg_combinebackup",
        full_dir,
        *incremental_dirs,
        "-o", output_dir
      ].join(" ")

      success, output = execute_command(cmd)
      raise RestoreError, "pg_combinebackup failed: #{output}" unless success
    end

    def configure_recovery(target_dir, target_time)
      recovery_signal = File.join(target_dir, "recovery.signal")
      FileUtils.touch(recovery_signal)

      postgresql_auto_conf = File.join(target_dir, "postgresql.auto.conf")
      
      wal_archiver = WalArchiver.new(config, storage)
      restore_command = wal_archiver.restore_command

      recovery_config = []
      recovery_config << "restore_command = '#{restore_command}'"
      
      if target_time
        recovery_config << "recovery_target_time = '#{target_time.iso8601}'"
        recovery_config << "recovery_target_action = 'promote'"
      end

      File.open(postgresql_auto_conf, "a") do |f|
        f.puts "\n# Recovery configuration added by ManagedPgBackups"
        recovery_config.each { |line| f.puts line }
      end

      puts "Recovery configuration written to #{postgresql_auto_conf}"
      puts "Place recovery.signal file: #{recovery_signal}"
      puts "\nTo complete restore:"
      puts "1. Stop your PostgreSQL server if running"
      puts "2. Replace your data directory with: #{target_dir}"
      puts "3. Start PostgreSQL - it will enter recovery mode automatically"
    end

    def execute_command(cmd)
      stdout, stderr, status = Open3.capture3(cmd)
      output = stdout + stderr
      
      [status.success?, output]
    end
  end

  class RestoreError < Error; end
end
