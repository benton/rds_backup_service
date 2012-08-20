module RDSDump
  # Backs up the contents of a single RDS database to S3
  class BackupJob

    @queue = :backups

    attr_reader :rds_id, :account_name, :options
    attr_reader :backup_id, :status, :status_url, :message
    attr_reader :requested

    # Constructor.
    # @param [String] rds_instance_id the ID of the RDS instance to backup
    # @param [String] account_name the account key from config/accounts.yml
    # @param [Hash] options optional additional parameters:
    #  - :backup_id - a unique ID for this job, if necessary
    #  - :requested - a Time when this job was requested
    def initialize(rds_instance_id, account_name, options = {})
      @rds_id, @account_name, @options = rds_instance_id, account_name, options
      @log        = FogTracker.default_logger(STDOUT)
      @backup_id  = options['backup_id'] || "%016x" % (rand * 0xffffffffffffffff)
      @requested  = options['requested'] ? Time.parse(options['requested']) : Time.now
      @status     = 200
      @message    = "queued"
      @s3         = RDSDump.s3
      @config     = RDSDump.settings
      @bucket     = @config['backup_bucket']
      @s3_path    = "#{@config['backup_prefix']}/"+
                    "#{requested.strftime("%Y/%m/%d")}/#{rds_id}/#{backup_id}"
    end

    # returns a JSON-format String representation of this backup job
    def to_json
      JSON.pretty_generate({
        backup_job_id:  backup_id,
        rds_instance:   rds_id,
        account_name:   account_name,
        backup_status:  status,
        status_message: message,
        status_url:     status_url,
      })
    end

    # Writes this job's JSON representation to S3
    def write_to_s3
      status_path = "#{@s3_path}/status.json"
      @s3.put_object(@bucket, status_path, "#{to_json}\n")
      unless @status_url
      expire_date = Time.now + (3600 * 24)  # one day from now
        @status_url = @s3.get_object_http_url(@bucket, status_path, expire_date)
        @s3.put_object(@bucket, status_path, "#{to_json}\n")
      end
    end

    # Entry point for business logic. Called by the Resque framework.
    # Parameters are the same as for #initialize()
    def self.perform(rds_instance_id, account_name, options = {})
      job = BackupJob.new(rds_instance_id, account_name, options).perform_backup
    end

    # Top-level, long-running method for performing the backup.
    def perform_backup
      update_status "Backing up #{rds_id} from account #{account_name}"
      rds = ::Fog::AWS::RDS.new(
        RDSDump.read_rds_accounts[account_name]['credentials']
      )
      original_server = rds.servers.get(rds_id)
      update_status "Waiting for RDS instance #{original_server.id}"
      original_server.wait_for { ready? }

      # Snapshot the RDS
      snapshot_id = "rds-dump-service-#{rds_id}-#{@backup_id}"
      update_status "Creating snapshot #{snapshot_id} from RDS #{rds_id}"
      snapshot = rds.snapshots.create(id: snapshot_id, instance_id: rds_id)
      update_status "Waiting for snapshot #{snapshot_id}"
      snapshot.wait_for { ready? }

      # Create a new RDS from the snapshot
      update_status "Creating snapshot #{snapshot_id} from RDS #{rds_id}"
      new_rds_id = "rds-dump-service-#{backup_id}"
      update_status "Booting new RDS #{new_rds_id} from snapshot #{snapshot_id}"
      response = rds.restore_db_instance_from_db_snapshot(snapshot.id, new_rds_id,
        'DBInstanceClass' => original_server.flavor_id )
      new_instance = rds.servers.get new_rds_id

      # Destroy the snapshot
      update_status "Waiting for new RDS instance #{new_instance.id}"
      new_instance.wait_for { ready? }
      update_status "Deleting snapshot #{snapshot_id}"
      snapshot.destroy

      # Update the Master Password and apply the tightened RDS Security Group
      update_status "Modifying RDS attributes for new RDS #{new_instance.id}"
      random_password = "%016x" % (rand * 0xffffffffffffffff)
      rds.modify_db_instance(new_instance.id, true, {
        'DBParameterGroupName'  => original_server.db_parameter_groups.
                                    first['DBParameterGroupName'],
        'DBSecurityGroups'      => [ @config['rds_security_group'] ],
        'MasterUserPassword'    => random_password,
      })
      update_status "Waiting for new attributes on RDS #{new_instance.id}"
      new_instance.reload
      new_instance.wait_for { ready? }

      # Connect to the RDS server, and dump the database to a temp dir
      
      # Destroy the temporary RDS instance
      update_status "Deleting RDS instance #{new_instance.id}"
      #new_instance.destroy

      # Compress the SQL dump
      # Upload the compressed SQL file to S3
    end

    # Writes a new status message to the log, and writes the job info to S3
    def update_status(message, new_status = nil)
      @message  = message
      @status   = new_status if new_status
      @log.info message
      write_to_s3
    end

  end
end
