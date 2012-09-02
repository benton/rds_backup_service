# The top-level project module. Contains some static helper methods.
module RDSBackup
  require 'fog'
  require 'tmpdir'
  require 'ohai'
  PROJECT_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
  require "#{PROJECT_DIR}/lib/rds_backup_service/version"

  # Loads account information defined in config/accounts.yml, or
  # ENV['RDS_ACCOUNTS_FILE'].
  # @param account_file the path to a YAML file (see accounts.yml.example).
  # @return [Array<Hash>] an Array of Hashes representing the account info.
  def self.read_accounts(account_file = ENV['RDS_ACCOUNTS_FILE'])
    YAML::load(File.read(account_file || "./config/accounts.yml"))
  end

  # Loads account information defined in account_file, and returns only those
  # entries that repesent RDS accounts.
  def self.rds_accounts
    RDSBackup.read_accounts.select{|id,acc| acc['service'] == 'RDS'}
  end

  # Returns a new connection to the AWS EC2 service (Fog::Compute::AWS)
  def self.ec2
    accts = RDSBackup.read_accounts.select{|id,acc| acc['service'] == 'Compute'}
    raise "At least one S3 account must be defined" if accts.empty?
    Fog::Compute::AWS.new(accts.first[1]['credentials'])
  end

  # Returns a new connection to the AWS S3 service (Fog::Storage::AWS)
  def self.s3
    accts = RDSBackup.read_accounts.select{|id,acc| acc['service'] == 'Storage'}
    raise "At least one S3 account must be defined" if accts.empty?
    Fog::Storage::AWS.new(accts.first[1]['credentials'])
  end

  # Returns the configuration Hash read from config/s3_account.yml
  # or ENV['RDSDUMP_SETTINGS_FILE'].
  def self.settings(settings_file = ENV['RDS_SETTINGS_FILE'])
    { # here are some defaults
      'rds_security_group'  => 'rds-backup-service',
      'ec2_security_group'  => 'rds-backup-service',
      'tmp_dir'             => Dir.tmpdir,
    }.merge(YAML::load(
      File.read(settings_file || "./config/settings.yml")))
  end

  # Defines the root URI path of the web service.
  # @return [String] the root URI path of the web service
  def self.root
    "/api/v#{RDSBackup::API_VERSION}"
  end

  def self.default_logger(output = nil)
    logger = ::Logger.new(output)
    logger.sev_threshold = Logger::INFO
    logger.formatter = proc {|lvl, time, prog, msg| "#{lvl}: #{msg}\n"}
    logger
  end

  # Returns a Fog RDS entity for a given an RDS ID. Polls all accounts.
  # The account name is attached to the result as 'tracker_account[:name]'.
  # @param [String] the name of the desired RDS entity
  # @return [Fog::AWS::RDS::Server] the RDS instance, or nil if not found
  def self.get_rds(rds_id)
    ::FogTracker::Tracker.new(RDSBackup.rds_accounts).update.
      select{|rds| rds.identity == rds_id}.first
  end

end
