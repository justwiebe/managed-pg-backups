# frozen_string_literal: true

module ManagedPgBackups
  module Storage
    class Base
      def initialize(config)
        @config = config
      end

      # Upload a file or directory to storage
      # @param local_path [String] Path to local file or directory
      # @param remote_path [String] Destination path in storage
      # @return [Boolean] Success status
      def upload(local_path, remote_path)
        raise NotImplementedError, "Subclasses must implement #upload"
      end

      # Download a file or directory from storage
      # @param remote_path [String] Path in storage
      # @param local_path [String] Destination local path
      # @return [Boolean] Success status
      def download(remote_path, local_path)
        raise NotImplementedError, "Subclasses must implement #download"
      end

      # List files in storage at given path
      # @param remote_path [String] Path in storage
      # @return [Array<String>] List of file paths
      def list(remote_path)
        raise NotImplementedError, "Subclasses must implement #list"
      end

      # Delete a file or directory from storage
      # @param remote_path [String] Path in storage
      # @return [Boolean] Success status
      def delete(remote_path)
        raise NotImplementedError, "Subclasses must implement #delete"
      end

      # Check if a file exists in storage
      # @param remote_path [String] Path in storage
      # @return [Boolean] Exists status
      def exists?(remote_path)
        raise NotImplementedError, "Subclasses must implement #exists?"
      end
    end
  end
end
