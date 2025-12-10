# frozen_string_literal: true

require "open3"
require "fileutils"

module ManagedPgBackups
  class BackupManager
    attr_reader :config, :storage, :backup_chain

    def initialize(config, storage, backup_chain)
      @config = config
      @storage = storage
      @backup_chain = backup_chain
    end

    def perform_full_backup
      timestamp = Time.now.utc.strftime("%Y%m%d_%H%M%S")
      backup_dir = "backups/full_#{timestamp}"
      manifest_name = "backup_manifest_#{timestamp}"
      
      temp_dir = File.join(Dir.tmpdir, "pg_backup_#{timestamp}")
      FileUtils.mkdir_p(temp_dir)

      begin
        cmd = build_pg_basebackup_command(temp_dir, manifest_name)
        success, output = execute_command(cmd)
        
        raise BackupError, "pg_basebackup failed: #{output}" unless success

        manifest_path = File.join(temp_dir, manifest_name)
        raise BackupError, "Manifest file not found" unless File.exist?(manifest_path)

        storage.upload(temp_dir, backup_dir)
        storage.upload(manifest_path, "manifests/#{manifest_name}")

        backup_chain.register_full_backup(
          backup_dir,
          "manifests/#{manifest_name}"
        )

        { success: true, backup_dir: backup_dir, manifest: manifest_name }
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
      end
    end

    def perform_incremental_backup
      latest_chain = backup_chain.latest_chain
      raise BackupError, "No full backup found" unless latest_chain

      manifest_path = backup_chain.latest_manifest_for_chain(latest_chain["chain_id"])
      raise BackupError, "No manifest found for chain" unless manifest_path

      temp_manifest = File.join(Dir.tmpdir, "parent_manifest_#{SecureRandom.hex(8)}")
      storage.download(manifest_path, temp_manifest)

      timestamp = Time.now.utc.strftime("%Y%m%d_%H%M%S")
      backup_dir = "backups/incremental_#{timestamp}"
      manifest_name = "backup_manifest_#{timestamp}"
      
      temp_dir = File.join(Dir.tmpdir, "pg_backup_#{timestamp}")
      FileUtils.mkdir_p(temp_dir)

      begin
        cmd = build_pg_basebackup_command(temp_dir, manifest_name, temp_manifest)
        success, output = execute_command(cmd)
        
        raise BackupError, "pg_basebackup failed: #{output}" unless success

        new_manifest_path = File.join(temp_dir, manifest_name)
        raise BackupError, "Manifest file not found" unless File.exist?(new_manifest_path)

        storage.upload(temp_dir, backup_dir)
        storage.upload(new_manifest_path, "manifests/#{manifest_name}")

        backup_chain.register_incremental_backup(
          latest_chain["chain_id"],
          backup_dir,
          "manifests/#{manifest_name}",
          manifest_path
        )

        { success: true, backup_dir: backup_dir, manifest: manifest_name }
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
        FileUtils.rm_f(temp_manifest) if File.exist?(temp_manifest)
      end
    end

    private

    def build_pg_basebackup_command(output_dir, manifest_name, parent_manifest = nil)
      cmd = [
        "pg_basebackup",
        "-D", output_dir,
        "-F", "p",
        "--wal-method=stream",
        "--manifest-path=#{manifest_name}",
        "--checkpoint=fast",
        "--progress"
      ]

      if parent_manifest
        cmd << "--incremental=#{parent_manifest}"
      end

      cmd.join(" ")
    end

    def execute_command(cmd)
      stdout, stderr, status = Open3.capture3(config.pg_env, cmd)
      output = stdout + stderr
      
      [status.success?, output]
    end
  end

  class BackupError < Error; end
end
