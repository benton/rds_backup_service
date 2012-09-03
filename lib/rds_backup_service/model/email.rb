require 'mail'
module RDSBackup
  # an email representation of a Job, that can send itself to recipients.
  class Email

    attr_reader :job

    def initialize(backup_job)
      @job = backup_job
    end

    def send!
      raise "job #{job.backup_id} has no email option" unless job.options['email']
      main_text = body_text # define local variables for closure over Mail.new
      recipients, header = job.options['email'], "Backup of RDS #{job.rds_id}"
      mail = Mail.new do
        from    'rdsbackupservice@mdsol.com'
        to      recipients
        subject header
        body    "#{main_text}\n"
      end
      mail.deliver!
    end

    def body_text
      msg = "Hello.\n\n"
      if job.status == 200
        msg += "Your backup of database #{job.rds_id} is complete.\n"+
          (job.files.empty? ? "" : "Output is at #{job.files.first[:url]}\n")
      else
        msg += "Your backup is incomplete: #{job.status}\n"
      end
      msg += "Job status is at #{job.status_url}"
    end

  end
end
