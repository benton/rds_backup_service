# The top-level project module. Contains some static helper methods.
module RDSBackup
  require 'fog'

  PROJECT_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
  require "#{PROJECT_DIR}/lib/rds_backup_service/version"

  # Loads account information defined in account_file, or ENV['RDS_ACCOUNTS_FILE'].
  # @param account_file the path to a YAML file (see accounts.yml.example).
  # @return [Array<Hash>] an Array of Hashes representing the account info.
  def self.read_rds_accounts(account_file = ENV['RDS_ACCOUNTS_FILE'])
    YAML::load(File.read(account_file || "#{PROJECT_DIR}/config/rds_accounts.yml"))
  end

  # Returns a new connection to the AWS S3 service (Fog::Storage::AWS),
  # with the credentials from config/s3_account.yml or ENV['S3_ACCOUNT_FILE'].
  def self.s3(confg_file = ENV['S3_ACCOUNT_FILE'])
    s3_config = YAML::load(File.read(
      account_file ||= "#{PROJECT_DIR}/config/s3_account.yml"))
    Fog::Storage::AWS.new(
      aws_access_key_id:     s3_config['aws_access_key_id'],
      aws_secret_access_key: s3_config['aws_secret_access_key'],
    )
  end

  # Returns the configuration Hash read from config/s3_account.yml
  # or ENV['RDSDUMP_SETTINGS_FILE'].
  def self.settings(settings_file = ENV['RDSDUMP_SETTINGS_FILE'])
    { # here are some defaults
      'tmp_dir' => Dir.tmpdir
    }.merge(YAML::load(
      File.read(settings_file || "#{PROJECT_DIR}/config/settings.yml")))
  end

  # Defines the root URI path of the web service.
  # @return [String] the root URI path of the web service
  def self.root
    "/api/v#{RDSBackup::API_VERSION}"
  end

  # Checks all defined RDS accounts to see if the security group exists.
  # Raises an Exception if that's not true.
  def self.check_setup
    group = RDSBackup.settings['rds_security_group']
    errors = RDSBackup.read_rds_accounts.inject([]) do |errors, account|
      unless ::Fog::AWS::RDS.new(account[1]['credentials']).security_groups.get group
        errors.push "SecurityGroup #{group} not found in RDS account #{account[0]}"
      end
      errors
    end
    raise errors.join("\n") unless errors.empty?
  end

end

# Recursively load all ruby files from the models directory
Dir[File.join(File.dirname(__FILE__), "model/*.rb")].each {|file| require file}