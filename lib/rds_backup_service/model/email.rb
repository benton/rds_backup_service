require 'mail'
module RDSBackup
  # an email representation of a Job, that can send itself to recipients.
  class Email

    attr_reader :job, :settings

    # constructor - requires an RDSBackup::Job
    def initialize(backup_job)
      @job, @settings = backup_job, RDSBackup.settings
    end

    # Attempts to send email through local ESMTP port 25.
    # Raises an Exception on failure.
    def send!
      raise "job #{job.backup_id} has no email option" unless job.options[:email]
      # define local variables for closure over Mail.new
      from_address  = settings['email_from']
      to_address    = job.options[:email]
      subject_text  = "Backup of RDS #{job.rds_id} (job ID #{job.backup_id})"
      body_text     = body
      mail = Mail.new do
        from    from_address
        to      to_address
        subject subject_text
        body    "#{body_text}\n"
      end
      mail.deliver!
    end

    # defines the body of a Job's status email
    def body
      msg = "Hello.\n\n"
      if job.status == 200
        msg += "Your backup of database #{job.rds_id} is complete.\n"+
          (job.files.empty? ? "" : "Output is at #{job.files.first[:url]}\n")
      else
        msg += "Your backup is incomplete. (job ID #{job.backup_id})\n"
      end
      msg += "Job status: #{job.message}"
    end

  end
end
