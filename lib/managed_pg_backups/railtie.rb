# frozen_string_literal: true

require "rails/railtie"

module ManagedPgBackups
  class Railtie < Rails::Railtie
    railtie_name :managed_pg_backups

    rake_tasks do
      load File.expand_path("../tasks/managed_pg_backups.rake", __dir__)
    end
  end
end
