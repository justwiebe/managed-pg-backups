# frozen_string_literal: true

require "yaml"
require "securerandom"
require "fileutils"

module ManagedPgBackups
  class BackupChain
    attr_reader :config, :metadata_path

    def initialize(config)
      @config = config
      @metadata_path = config.metadata_file_path
      ensure_metadata_file_exists
    end

    def load_metadata
      YAML.load_file(metadata_path) || { "chains" => [] }
    rescue StandardError
      { "chains" => [] }
    end

    def save_metadata(metadata)
      File.write(metadata_path, YAML.dump(metadata))
    end

    def register_full_backup(backup_path, manifest_path)
      metadata = load_metadata
      chain_id = SecureRandom.uuid
      
      backup_record = {
        "chain_id" => chain_id,
        "type" => "full",
        "backup_id" => SecureRandom.uuid,
        "timestamp" => Time.now.utc.iso8601,
        "backup_path" => backup_path,
        "manifest_path" => manifest_path,
        "incrementals" => []
      }

      metadata["chains"] ||= []
      metadata["chains"] << backup_record
      save_metadata(metadata)

      backup_record
    end

    def register_incremental_backup(chain_id, backup_path, manifest_path, parent_manifest_path)
      metadata = load_metadata
      chain = metadata["chains"].find { |c| c["chain_id"] == chain_id }
      
      raise BackupChainError, "Chain not found: #{chain_id}" unless chain

      incremental_record = {
        "backup_id" => SecureRandom.uuid,
        "timestamp" => Time.now.utc.iso8601,
        "backup_path" => backup_path,
        "manifest_path" => manifest_path,
        "parent_manifest_path" => parent_manifest_path
      }

      chain["incrementals"] ||= []
      chain["incrementals"] << incremental_record
      save_metadata(metadata)

      incremental_record
    end

    def latest_chain
      metadata = load_metadata
      return nil if metadata["chains"].empty?

      metadata["chains"].max_by { |c| c["timestamp"] }
    end

    def get_chain(chain_id)
      metadata = load_metadata
      metadata["chains"].find { |c| c["chain_id"] == chain_id }
    end

    def all_chains
      metadata = load_metadata
      metadata["chains"] || []
    end

    def latest_manifest_for_chain(chain_id)
      chain = get_chain(chain_id)
      return nil unless chain

      if chain["incrementals"]&.any?
        chain["incrementals"].last["manifest_path"]
      else
        chain["manifest_path"]
      end
    end

    def get_restore_chain(chain_id, target_time: nil)
      chain = get_chain(chain_id)
      return nil unless chain

      backups = [chain]
      
      if target_time
        chain["incrementals"]&.each do |inc|
          break if Time.parse(inc["timestamp"]) > target_time
          backups << inc
        end
      else
        backups.concat(chain["incrementals"] || [])
      end

      backups
    end

    def cleanup_old_chains
      metadata = load_metadata
      chains = metadata["chains"] || []
      
      return if chains.size <= config.retention_count

      sorted_chains = chains.sort_by { |c| c["timestamp"] }
      chains_to_remove = sorted_chains[0...(chains.size - config.retention_count)]

      chains_to_remove.each do |chain|
        delete_chain(chain["chain_id"])
      end
    end

    def delete_chain(chain_id)
      metadata = load_metadata
      chain = metadata["chains"].find { |c| c["chain_id"] == chain_id }
      
      return false unless chain

      storage = create_storage
      storage.delete(chain["backup_path"]) if chain["backup_path"]
      storage.delete(chain["manifest_path"]) if chain["manifest_path"]
      
      chain["incrementals"]&.each do |inc|
        storage.delete(inc["backup_path"]) if inc["backup_path"]
        storage.delete(inc["manifest_path"]) if inc["manifest_path"]
      end

      metadata["chains"].reject! { |c| c["chain_id"] == chain_id }
      save_metadata(metadata)

      true
    end

    private

    def ensure_metadata_file_exists
      return if File.exist?(metadata_path)

      dir = File.dirname(metadata_path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      save_metadata({ "chains" => [] })
    end

    def create_storage
      case config.storage_type
      when :local
        Storage::Local.new(config)
      when :s3
        Storage::S3.new(config)
      else
        raise BackupChainError, "Unknown storage type: #{config.storage_type}"
      end
    end
  end

  class BackupChainError < Error; end
end
