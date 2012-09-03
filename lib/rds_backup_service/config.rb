module RDSBackup
  module Config

    # Attempts to set up the EC2 and RDS security groups as specified in the
    # configuration. Raises an Exception on errors. Best if run from EC2.
    def self.setup_security_groups(logger = nil)
      log = logger || RDSBackup.default_logger(STDOUT)
      # Configuration
      log.info "Scanning system..."
      (system = Ohai::System.new).all_plugins
      log.info "Reading config files..."
      settings = RDSBackup.settings
      ec2_group_name = settings['ec2_security_group']
      rds_group_name = settings['rds_security_group']
      ec2 = RDSBackup.ec2

      # EC2 Security Group creation
      log.info "Checking EC2 for Security Group #{ec2_group_name}"
      unless ec2_group = ec2.security_groups.get(ec2_group_name)
        log.info "Creating EC2 Security group #{ec2_group_name}"
        ec2_group = ec2.security_groups.create(:name => ec2_group_name,
          :description => 'Created by rds_backup_service')
      end

      # RDS Security Group creation and authorization
      RDSBackup.rds_accounts.each do |account_name, account_data|
        log.info "Checking account #{account_name} for "+
          "RDS Security group #{rds_group_name}"
        rds = ::Fog::AWS::RDS.new(account_data[:credentials])
        rds_group = rds.security_groups.get rds_group_name
        unless rds_group
          log.info "Creating security group #{rds_group_name} in #{account_name}"
          rds_group = rds.security_groups.create(:id => rds_group_name,
            :description => 'Created by rds_backup_service')
        end
        # Apply EC2 authorization to RDS Security Groups
        owner = ec2.security_groups.first.owner_id
        authorized = false
        rds_group.ec2_security_groups.each do |authorization|
          if (authorization['EC2SecurityGroupName'] == ec2_group_name) &&
            (authorization['EC2SecurityGroupOwnerId'] == owner)
              authorized = true
          end
        end
        unless authorized
          log.info "Authorizing EC2 Group for #{account_name}/#{rds_group_name}"
          rds_group.authorize_ec2_security_group(ec2_group_name, owner)
        end
      end

      # EC2 Security Group check for this host
      unless system[:ec2]
        log.warn "Not running in EC2 - open RDS groups to this host!"
      else
        unless this_host = ec2.servers.get(system[:ec2][:instance_id])
          log.warn "Not running in EC2 account #{s3_acc_name}!"
        else
          log.info "Running in EC2. Current Security Groups = #{this_host.groups}"
          unless this_host.groups.include? ec2_group_name
            log.warn "This host is not in Security Group #{ec2_group_name}!"
          end
        end
      end

    end
  end
end
