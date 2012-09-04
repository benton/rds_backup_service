module RDSBackup
  # convenience wrapper class for DelayedJob.
  # Parameters are the same as for RDSBackup::Job.initialize()
  class DelayedJob < Struct.new(:rds_id, :options)
    # Entry point for the DelayedJob framework.
    def perform
      RDSBackup::Job.new(rds_id, options).perform_backup
    end
  end
end
