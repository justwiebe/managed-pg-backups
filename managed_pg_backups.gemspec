require_relative 'lib/managed_pg_backups/version'

Gem::Specification.new do |spec|
  spec.name          = "managed_pg_backups"
  spec.version       = ManagedPgBackups::VERSION
  spec.authors       = ["Justin Wiebe"]
  spec.email         = ["justin@wiebes.world"]

  spec.summary       = "Automatic full and incremental Postgres backups and restores in Ruby on Rails. Save to local storage or an S3 bucket."
  spec.description   = "A longer description of your gem"
  spec.homepage      = "https://github.com/justwiebe/managed-pg-backups"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/justwiebe/managed-pg-backups"
  spec.metadata["changelog_uri"] = "https://github.com/justwiebe/managed-pg-backups/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  # spec.add_dependency "example-gem", "~> 1.0"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
