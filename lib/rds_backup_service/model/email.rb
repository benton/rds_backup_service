require 'mail'
module RDSBackup
  # an email representation of a Job, that can send itself to recipients.
  class Email

    attr_reader :job

    # constructor - requires an RDSBackup::Job
    def initialize(backup_job)
      @job = backup_job
    end

    # Attempts to send email through local ESMTP port 25.
    # Raises an Exception on failure.
    def send!
      raise "job #{job.backup_id} has no email option" unless job.options[:email]
      main_text = body_text # define local variables for closure over Mail.new
      recipients = job.options[:email]
      header = "Backup of RDS #{job.rds_id} (job ID #{job.backup_id})"
      mail = Mail.new do
        from    'rdsbackupservice@mdsol.com'
        to      recipients
        subject header
        body    "#{main_text}\n"
      end
      mail.deliver!
    end

    # defines the body of a Job's status email
    def body_text
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
