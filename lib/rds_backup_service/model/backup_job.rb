require 'fog_tracker'
require 'fileutils'
module RDSBackup
  # Backs up the contents of a single RDS database to S3
  class Job

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
      @log        = ::FogTracker.default_logger(STDOUT)
      @backup_id  = options['backup_id'] || "%016x" % (rand * 0xffffffffffffffff)
      @requested  = options['requested'] ? Time.parse(options['requested']) : Time.now
      @status     = 200
      @message    = "queued"
      @files      = []
      @s3         = RDSBackup.s3
      @config     = RDSBackup.settings
      @bucket     = @config['backup_bucket']
      @s3_path    = "#{@config['backup_prefix']}/"+
                    "#{requested.strftime("%Y/%m/%d")}/#{rds_id}/#{backup_id}"
      @snapshot_id  = "rds-backup-service-#{rds_id}-#{backup_id}"
      @new_rds_id   = "rds-backup-service-#{backup_id}"
      @new_password = "#{backup_id}"
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
      job = Job.new(rds_instance_id, account_name, options)
      begin
        job.perform_backup
      rescue Exception => e
        job.update_status "ERROR: #{e.message.split("\n").first}", 500
        raise e
      end
    end

    # Top-level, long-running method for performing the backup.
    # Builds up the instance state variables: @rds, @original_server,
    # @snapshot, @new_instance, @new_password, and @sql_file.
    def perform_backup
      update_status "Backing up #{rds_id} from account #{account_name}"
      create_disconnected_rds
      download_data_from_tmp_rds    # populates @sql_file
      delete_disconnected_rds
      upload_output_to_s3
      update_status "Backup of #{rds_id} complete"
    end

    # Step 1 of the overall process - create a disconnected copy of the RDS
    def create_disconnected_rds(new_rds_name = nil)
      @new_rds_id = new_rds_name if new_rds_name
      prepare_backup
      snapshot_original_rds
      create_tmp_rds_from_snapshot
      configure_tmp_rds
      wait_for_new_security_group
      wait_for_new_parameter_group # (reboots as needed)
      destroy_snapshot
    end

    # Queries RDS for any pre-existing entities associated with this job.
    # Also waits for the original RDS to become ready.
    def prepare_backup
      @rds = ::Fog::AWS::RDS.new(
        RDSBackup.read_rds_accounts[account_name]['credentials']
      )
      @original_server  = @rds.servers.get(rds_id)
      @snapshot         = @rds.snapshots.get @snapshot_id
      @new_instance     = @rds.servers.get @new_rds_id
    end

    # Snapshots the original RDS
    def snapshot_original_rds
      unless @new_instance || @snapshot
        update_status "Waiting for RDS instance #{@original_server.id}"
        @original_server.wait_for { ready? }
        update_status "Creating snapshot #{@snapshot_id} from RDS #{rds_id}"
        @snapshot = @rds.snapshots.create(id: @snapshot_id, instance_id: rds_id)
      end
    end

    # Creates a new RDS from the snapshot
    def create_tmp_rds_from_snapshot
      unless @new_instance
        update_status "Waiting for snapshot #{@snapshot_id}"
        @snapshot.wait_for { ready? }
        update_status "Booting new RDS #{@new_rds_id} from snapshot #{@snapshot.id}"
        @rds.restore_db_instance_from_db_snapshot(@snapshot.id,
          @new_rds_id, 'DBInstanceClass' => @original_server.flavor_id)
        @new_instance = @rds.servers.get @new_rds_id
      end
    end

    # Destroys the snapshot if it exists
    def destroy_snapshot
      if (@snapshot = @rds.snapshots.get @snapshot_id)
        update_status "Deleting snapshot #{@snapshot.id}"
        @snapshot.destroy
      end
    end

    # Updates the Master Password and applies the tightened RDS Security Group
    def configure_tmp_rds
      update_status "Waiting for instance #{@new_instance.id}..."
      @new_instance.wait_for { ready? }
      update_status "Modifying RDS attributes for new RDS #{@new_instance.id}"
      @rds.modify_db_instance(@new_instance.id, true, {
        'DBParameterGroupName'  => @original_server.db_parameter_groups.
                                    first['DBParameterGroupName'],
        'DBSecurityGroups'      => [ @config['rds_security_group'] ],
        'MasterUserPassword'    => @new_password,
      })
    end

    # Wait for the new RDS Security Group to become 'active'
    def wait_for_new_security_group
      old_group_name = @config['rds_security_group']
      update_status "Applying security group #{old_group_name}"+
        " to #{@new_instance.id}"
      @new_instance.wait_for {
        new_group = (db_security_groups.select do |group|
          group['DBSecurityGroupName'] == old_group_name
        end).first
        (new_group ? new_group['Status'] : 'Unknown') == 'active'
      }
    end

    # Wait for the new RDS Parameter Group to become 'in-sync'
    def wait_for_new_parameter_group
      old_name = @original_server.db_parameter_groups.first['DBParameterGroupName']
      update_status "Applying parameter group #{old_name} to #{@new_instance.id}"
      job = self  # save local var for closure in wait_for, below
      @new_instance.wait_for {
        new_group = (db_parameter_groups.select do |group|
          group['DBParameterGroupName'] == old_name
        end).first
        status = (new_group ? new_group['ParameterApplyStatus'] : 'Unknown')
        if (status == "pending-reboot")
          job.update_status "Rebooting RDS #{id} to apply ParameterGroup #{old_name}"
          reboot and wait_for { ready? }
        end
        status == 'in-sync' && ready?
      }
    end

    # Connects to the RDS server, and dumps the database to a temp dir
    def download_data_from_tmp_rds
      @new_instance.wait_for { ready? }
      db_name = @original_server.db_name
      db_user = @original_server.master_username
      update_status "Dumping database #{db_name} from #{@new_instance.id}"
      dump_time   = @snapshot ? Time.parse(@snapshot.created_at.to_s) : Time.now
      date_stamp  = dump_time.strftime("%Y-%m-%d-%H%M%S")
      @sql_file = "#{@config['tmp_dir']}/#{@s3_path}/#{db_name}.#{date_stamp}.sql.gz"
      hostname  = @new_instance.endpoint['Address']
      dump_cmd  = "mysqldump -u #{db_user} -h #{hostname} "+
        "-p#{@new_password} #{db_name} | gzip >#{@sql_file}"
      FileUtils.mkpath(File.dirname @sql_file)
      @log.debug "Executing command: #{dump_cmd}"
      `#{dump_cmd}`
    end

    # Destroys the temporary RDS instance
    def delete_disconnected_rds
      update_status "Deleting RDS instance #{@new_instance.id}"
      @new_instance.destroy
    end

    # Uploads the compressed SQL file to S3
    def upload_output_to_s3
      update_status "Uploading output file #{::File.basename @sql_file}"
      dump_path = "#{@s3_path}/#{::File.basename @sql_file}"
      @s3.put_object(@bucket, dump_path, File.read(@sql_file))
      upload = @s3.directories.get(@bucket).files.get dump_path
      @files = [ {
        name: ::File.basename(@sql_file),
        size: upload.content_length,
        url:  upload.url(Time.now + (3600 * 24 * 30))  # 30 days from now
      } ]
      @log.info "Deleting tmp directory #{File.dirname @sql_file}"
      FileUtils.rm_rf(File.dirname @sql_file)
    end

    # Writes a new status message to the log, and writes the job info to S3
    def update_status(message, new_status = nil)
      @message  = message
      @status   = new_status if new_status
      @status == 200 ? (@log.info message) : (@log.error message)
      write_to_s3 if @s3
    end

  end
end
