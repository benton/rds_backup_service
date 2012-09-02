desc "Attempts to set up the EC2 and RDS security groups"
namespace :setup do
  task :groups do
    RDSBackup::Config.setup_security_groups
  end
end
