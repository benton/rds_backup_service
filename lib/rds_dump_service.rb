%w{rubygems bundler}.each {|lib| require lib}
Bundler.setup
require File.join(File.dirname(__FILE__), "rds_dump_service/rds_dump_service")
