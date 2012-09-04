desc "Attempts to set up the rds_backup_service security groups"
namespace :setup do
  task :security_groups do
    RDSBackup::Config.setup_security_groups
  end
end
