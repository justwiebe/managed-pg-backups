# frozen_string_literal: true

require "aws-sdk-s3"
require "fileutils"

module ManagedPgBackups
  module Storage
    class S3 < Base
      def initialize(config)
        super
        @bucket_name = config.s3_bucket
        @client = Aws::S3::Client.new(
          region: config.s3_region,
          access_key_id: config.s3_access_key_id,
          secret_access_key: config.s3_secret_access_key
        )
        @resource = Aws::S3::Resource.new(client: @client)
        @bucket = @resource.bucket(@bucket_name)
      end

      def upload(local_path, remote_path)
        if File.directory?(local_path)
          upload_directory(local_path, remote_path)
        else
          upload_file(local_path, remote_path)
        end
        true
      rescue StandardError => e
        raise StorageError, "Failed to upload #{local_path} to S3: #{e.message}"
      end

      def download(remote_path, local_path)
        objects = list(remote_path)
        
        if objects.empty?
          # Try downloading as a single file
          download_file(remote_path, local_path)
        else
          # Download as directory
          download_directory(remote_path, local_path, objects)
        end
        true
      rescue StandardError => e
        raise StorageError, "Failed to download #{remote_path} from S3: #{e.message}"
      end

      def list(remote_path)
        prefix = remote_path.end_with?("/") ? remote_path : "#{remote_path}/"
        @bucket.objects(prefix: prefix).map(&:key)
      rescue StandardError => e
        raise StorageError, "Failed to list #{remote_path} in S3: #{e.message}"
      end

      def delete(remote_path)
        objects = list(remote_path)
        
        if objects.empty?
          # Try deleting as a single file
          @bucket.object(remote_path).delete
        else
          # Delete all objects with this prefix
          @bucket.objects(prefix: remote_path).batch_delete!
        end
        true
      rescue StandardError => e
        raise StorageError, "Failed to delete #{remote_path} from S3: #{e.message}"
      end

      def exists?(remote_path)
        @bucket.object(remote_path).exists?
      rescue StandardError => e
        false
      end

      private

      def upload_file(local_path, remote_path)
        obj = @bucket.object(remote_path)
        obj.upload_file(local_path)
      end

      def upload_directory(local_path, remote_path)
        Dir.glob(File.join(local_path, "**", "*")).each do |file|
          next unless File.file?(file)

          relative_path = file.sub(local_path + "/", "")
          s3_key = File.join(remote_path, relative_path)
          upload_file(file, s3_key)
        end
      end

      def download_file(remote_path, local_path)
        FileUtils.mkdir_p(File.dirname(local_path))
        obj = @bucket.object(remote_path)
        obj.download_file(local_path)
      end

      def download_directory(remote_path, local_path, objects)
        FileUtils.mkdir_p(local_path)
        prefix = remote_path.end_with?("/") ? remote_path : "#{remote_path}/"
        
        objects.each do |key|
          relative_path = key.sub(prefix, "")
          local_file = File.join(local_path, relative_path)
          download_file(key, local_file)
        end
      end
    end
  end
end
