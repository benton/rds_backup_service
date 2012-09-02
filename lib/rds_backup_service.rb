%w{rubygems bundler}.each {|lib| require lib}
Bundler.setup

# Load the other files in this library
%w{ version rds_backup_service config model/backup_job }.each do |file|
  require File.join(File.dirname(__FILE__), "rds_backup_service/#{file}")
end
