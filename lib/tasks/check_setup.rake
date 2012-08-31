desc "Run some configuration checks - raises Exception on failure"
namespace :test do
  task :setup do
    RDSBackup.check_setup
  end
end
