desc "Attempts to set up the rds_backup_service security groups"
namespace :setup do
  task :rds_backup_groups do
    require 'rds_backup_service'
    RDSBackup::Config.setup_security_groups
  end
end
