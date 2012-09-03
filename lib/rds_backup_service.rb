%w{rubygems bundler}.each {|lib| require lib}
Bundler.setup

# Load all the other files in this library, except the service
%w{ version rds_backup_service config
    model/backup_job model/delayed_job }.each do |file|
  require File.join(File.dirname(__FILE__), "rds_backup_service/#{file}")
end
