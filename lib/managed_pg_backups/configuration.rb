# frozen_string_literal: true

module ManagedPgBackups
  class Configuration
    attr_accessor :database_host, :database_port, :database_name, :database_user, :database_password
    attr_accessor :storage_type, :storage_path, :s3_bucket, :s3_region, :s3_access_key_id, :s3_secret_access_key
    attr_accessor :full_backup_schedule, :incremental_backup_schedule
    attr_accessor :retention_count, :metadata_file_path
    attr_accessor :wal_archive_path

    def initialize
      # Database defaults
      @database_host = ENV.fetch("PGHOST", "localhost")
      @database_port = ENV.fetch("PGPORT", "5432").to_i
      @database_name = ENV.fetch("PGDATABASE", "postgres")
      @database_user = ENV.fetch("PGUSER", "postgres")
      @database_password = ENV.fetch("PGPASSWORD", nil)

      # Storage defaults
      @storage_type = :local # :local or :s3
      @storage_path = ENV.fetch("BACKUP_STORAGE_PATH", "./backups")
      @s3_bucket = ENV.fetch("S3_BACKUP_BUCKET", nil)
      @s3_region = ENV.fetch("S3_BACKUP_REGION", "us-east-1")
      @s3_access_key_id = ENV.fetch("AWS_ACCESS_KEY_ID", nil)
      @s3_secret_access_key = ENV.fetch("AWS_SECRET_ACCESS_KEY", nil)

      # Schedule defaults (cron-like format)
      @full_backup_schedule = "0 2 * * 0" # Weekly on Sunday at 2am
      @incremental_backup_schedule = "0 2 * * *" # Daily at 2am

      # Retention defaults
      @retention_count = 4 # Keep 4 full backup chains

      # Metadata storage
      @metadata_file_path = File.join(@storage_path, "backup_metadata.yml")

      # WAL archive path
      @wal_archive_path = File.join(@storage_path, "wal_archive")
    end

    def validate!
      raise ConfigurationError, "database_name is required" if database_name.nil? || database_name.empty?
      raise ConfigurationError, "database_user is required" if database_user.nil? || database_user.empty?

      if storage_type == :s3
        raise ConfigurationError, "s3_bucket is required for S3 storage" if s3_bucket.nil? || s3_bucket.empty?
        raise ConfigurationError, "s3_access_key_id is required for S3 storage" if s3_access_key_id.nil?
        raise ConfigurationError, "s3_secret_access_key is required for S3 storage" if s3_secret_access_key.nil?
      elsif storage_type == :local
        raise ConfigurationError, "storage_path is required for local storage" if storage_path.nil? || storage_path.empty?
      else
        raise ConfigurationError, "storage_type must be :local or :s3"
      end

      true
    end

    def connection_string
      uri = "postgresql://#{database_user}"
      uri += ":#{database_password}" if database_password
      uri += "@#{database_host}:#{database_port}/#{database_name}"
      uri
    end

    def pg_env
      {
        "PGHOST" => database_host,
        "PGPORT" => database_port.to_s,
        "PGDATABASE" => database_name,
        "PGUSER" => database_user
      }.tap do |env|
        env["PGPASSWORD"] = database_password if database_password
      end
    end
  end

  class ConfigurationError < Error; end
end
