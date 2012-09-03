module RDSBackup
  class DelayedJob < Struct.new(:rds_id, :options)
    def perform
      RDSBackup::Job.new(rds_id, options).perform_backup
    end
  end
end
