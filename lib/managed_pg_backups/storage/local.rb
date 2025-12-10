# frozen_string_literal: true

require "fileutils"

module ManagedPgBackups
  module Storage
    class Local < Base
      def initialize(config)
        super
        @base_path = config.storage_path
        FileUtils.mkdir_p(@base_path) unless Dir.exist?(@base_path)
      end

      def upload(local_path, remote_path)
        destination = File.join(@base_path, remote_path)
        FileUtils.mkdir_p(File.dirname(destination))

        if File.directory?(local_path)
          FileUtils.cp_r(local_path, destination)
        else
          FileUtils.cp(local_path, destination)
        end

        true
      rescue StandardError => e
        raise StorageError, "Failed to upload #{local_path}: #{e.message}"
      end

      def download(remote_path, local_path)
        source = File.join(@base_path, remote_path)
        raise StorageError, "File not found: #{remote_path}" unless File.exist?(source)

        FileUtils.mkdir_p(File.dirname(local_path))

        if File.directory?(source)
          FileUtils.cp_r(source, local_path)
        else
          FileUtils.cp(source, local_path)
        end

        true
      rescue StandardError => e
        raise StorageError, "Failed to download #{remote_path}: #{e.message}"
      end

      def list(remote_path)
        full_path = File.join(@base_path, remote_path)
        return [] unless Dir.exist?(full_path)

        Dir.glob(File.join(full_path, "**", "*"))
           .select { |f| File.file?(f) }
           .map { |f| f.sub(@base_path + "/", "") }
      rescue StandardError => e
        raise StorageError, "Failed to list #{remote_path}: #{e.message}"
      end

      def delete(remote_path)
        full_path = File.join(@base_path, remote_path)
        return true unless File.exist?(full_path)

        if File.directory?(full_path)
          FileUtils.rm_rf(full_path)
        else
          FileUtils.rm(full_path)
        end

        true
      rescue StandardError => e
        raise StorageError, "Failed to delete #{remote_path}: #{e.message}"
      end

      def exists?(remote_path)
        File.exist?(File.join(@base_path, remote_path))
      end
    end

    class StorageError < Error; end
  end
end
