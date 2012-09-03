# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "rds_backup_service/version"

Gem::Specification.new do |s|
  s.name        = "rds_backup_service"
  s.version     = RDSBackup::VERSION
  s.authors     = ["Benton Roberts"]
  s.email       = ["benton@bentonroberts.com"]
  s.homepage    = "http://github.com/benton/rds_backup_service"
  s.summary     = %q{Provides a REST API for backing up live RDS instances }+
                  %q{to S3 as a compressed SQL file.}
  s.description = %q{Provides a REST API for backing up live RDS instances }+
                  %q{to S3 as a compressed SQL file.}
  s.rubyforge_project = "rds_backup_service"

  # This project is both a Gem and an Application,
  # so the Gemfile.lock is included in the repo for application users,
  # but excluded from the packaged Gem, for middleware use.
  git_files       = `git ls-files`.split("\n")    # Read all files in the repo,
  git_files.delete "Gemfile.lock"                 # remove Gemfile.lock, and
  s.files         = git_files                     # use the result in the Gem.

  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # Runtime dependencies
  s.add_dependency "sinatra"
  s.add_dependency "fog_tracker", ">=0.4.0"
  s.add_dependency "resque"
  s.add_dependency "mail"
  s.add_dependency "ohai"

  # Development / Test dependencies
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec"
  s.add_development_dependency "guard"
  s.add_development_dependency "guard-rspec"
  s.add_development_dependency "ruby_gntp"
end
