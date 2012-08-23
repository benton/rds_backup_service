require 'fileutils'
module RDSDump
  # Backs up the contents of a single RDS database to S3
  class BackupJob

    @queue = :backups

    attr_reader :backup_id, :rds_id, :account_name, :options
    attr_reader :status, :status_url, :message, :files, :requested

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
      @files      = []
    end

    # returns a JSON-format String representation of this backup job
    def to_json
      JSON.pretty_generate({
        rds_instance:   rds_id,
        account_name:   account_name,
        backup_status:  status,
        status_message: message,
        status_url:     status_url,
        files:          files,
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

    # Entry point for the Resque framework.
    # Parameters are the same as for #initialize()
    def self.perform(rds_instance_id, account_name, options = {})
      job = BackupJob.new(rds_instance_id, account_name, options).perform_backup
    end

    # Top-level, long-running method for performing the backup.
    # Builds up the instance state variables: @rds, @original_server,
    # @snapshot, @new_instance, @new_password, and @sql_file.
    def perform_backup
      update_status "Backing up #{rds_id} from account #{account_name}"
      prepare_backup                # populates @rds and @original_server
      snapshot_original_rds         # populates @snapshot
      create_tmp_rds_from_snapshot  # populates @new_instance
      destroy_snapshot
      configure_tmp_rds             # populates @new_password
      # reboot_tmp_rds_if_needed    # TODO
      download_data_from_tmp_rds    # populates @sql_file
      delete_tmp_rds
      upload_output_to_s3
      update_status "Backup complete"
    end

    # Connects to the RDS web service, and waits for the instance to be ready
    def prepare_backup
      @rds = ::Fog::AWS::RDS.new(
        RDSDump.read_rds_accounts[account_name]['credentials']
      )
      @original_server = @rds.servers.get(rds_id)
      update_status "Waiting for RDS instance #{@original_server.id}"
      @original_server.wait_for { ready? }
    end

    # Snapshots the original RDS
    def snapshot_original_rds
      snapshot_id = "rds-dump-service-#{rds_id}-#{backup_id}"
      update_status "Creating snapshot #{snapshot_id} from RDS #{rds_id}"
      @snapshot = @rds.snapshots.create(id: snapshot_id, instance_id: rds_id)
      update_status "Waiting for snapshot #{snapshot_id}"
      @snapshot.wait_for { ready? }
    end

    # Creates a new RDS from the snapshot
    def create_tmp_rds_from_snapshot
      new_rds_id = "rds-dump-service-#{backup_id}"
      update_status "Booting new RDS #{new_rds_id} from snapshot #{@snapshot.id}"
      response = @rds.restore_db_instance_from_db_snapshot(@snapshot.id,
        new_rds_id, 'DBInstanceClass' => @original_server.flavor_id)
      @new_instance = @rds.servers.get new_rds_id
    end

    # Destroys the snapshot
    def destroy_snapshot
      update_status "Waiting for new RDS instance #{@new_instance.id}"
      @new_instance.wait_for { ready? }
      update_status "Deleting snapshot #{@snapshot.id}"
      @snapshot.destroy
    end

    # Updates the Master Password and applies the tightened RDS Security Group
    def configure_tmp_rds
      update_status "Modifying RDS attributes for new RDS #{@new_instance.id}"
      @new_password = "%016x" % (rand * 0xffffffffffffffff)
      @rds.modify_db_instance(@new_instance.id, true, {
        'DBParameterGroupName'  => @original_server.db_parameter_groups.
                                    first['DBParameterGroupName'],
        'DBSecurityGroups'      => [ @config['rds_security_group'] ],
        'MasterUserPassword'    => @new_password,
      })
      @new_instance.reload
      @new_instance.wait_for { ready? }
    end

    # Connects to the RDS server, and dumps the database to a temp dir
    def download_data_from_tmp_rds
      db_name = @original_server.db_name
      db_user = @original_server.master_username
      update_status "Dumping database #{db_name} from #{@new_instance.id}"
      @sql_file = "/tmp/#{@s3_path}/#{db_name}.sql.gz"
      hostname  = @new_instance.endpoint['Address']
      dump_cmd  = "mysqldump -u #{db_user} -h #{hostname} "+
        "-p#{@new_password} #{db_name} | gzip >#{@sql_file}"
      FileUtils.mkpath(File.dirname @sql_file)
      @log.debug "Executing command: #{dump_cmd}"
      `#{dump_cmd}`
    end

    # Destroys the temporary RDS instance
    def delete_tmp_rds
      update_status "Deleting RDS instance #{@new_instance.id}"
      @new_instance.destroy
    end

    # Uploads the compressed SQL file to S3
    def upload_output_to_s3
      update_status "Uploading output file #{::File.basename @sql_file}"
      dump_path = "#{@s3_path}/#{::File.basename @sql_file}"
      @s3.put_object(@bucket, dump_path, File.read(@sql_file))
      expire_date = Time.now + (3600 * 24 * 30)  # 30 days from now
      output_url = @s3.get_object_http_url(@bucket, dump_path, expire_date)
      @files = [ { name: ::File.basename(@sql_file), url: output_url } ]
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
