# frozen_string_literal: true

require_relative "managed_pg_backups/version"
require_relative "managed_pg_backups/configuration"
require_relative "managed_pg_backups/storage/base"
require_relative "managed_pg_backups/storage/local"
require_relative "managed_pg_backups/storage/s3"
require_relative "managed_pg_backups/wal_archiver"
require_relative "managed_pg_backups/backup_chain"
require_relative "managed_pg_backups/backup_manager"
require_relative "managed_pg_backups/restore_manager"
require_relative "managed_pg_backups/scheduler"

# Load Railtie if Rails is present
require_relative "managed_pg_backups/railtie" if defined?(Rails)

module ManagedPgBackups
  class Error < StandardError; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      configuration.validate!
    end

    def storage
      @storage ||= case configuration.storage_type
                   when :local
                     Storage::Local.new(configuration)
                   when :s3
                     Storage::S3.new(configuration)
                   else
                     raise ConfigurationError, "Unknown storage type: #{configuration.storage_type}"
                   end
    end

    def backup_chain
      @backup_chain ||= BackupChain.new(configuration)
    end

    def backup_manager
      @backup_manager ||= BackupManager.new(configuration, storage, backup_chain)
    end

    def restore_manager
      @restore_manager ||= RestoreManager.new(configuration, storage, backup_chain)
    end

    def wal_archiver
      @wal_archiver ||= WalArchiver.new(configuration, storage)
    end

    def scheduler
      @scheduler ||= Scheduler.new(configuration, backup_manager, backup_chain)
    end

    def reset!
      @configuration = nil
      @storage = nil
      @backup_chain = nil
      @backup_manager = nil
      @restore_manager = nil
      @wal_archiver = nil
      @scheduler = nil
    end
  end
end
