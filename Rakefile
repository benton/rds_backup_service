# Set up bundler
%w{rubygems bundler bundler/gem_tasks}.each {|dep| require dep}
bundles = [:default]
Bundler.setup(:default)
case ENV['RACK_ENV']
when 'development'  then Bundler.setup(:default, :development)
when 'test'         then Bundler.setup(:default, :development, :test)
end

require 'rds_backup_service'
require 'resque/tasks'
ENV['TERM_CHILD'] = '1'

# Load all tasks from 'lib/tasks'
Dir["#{File.dirname(__FILE__)}/lib/tasks/*.rake"].sort.each {|ext| load ext}

desc 'Default: runs all tests'
task :default => :spec
