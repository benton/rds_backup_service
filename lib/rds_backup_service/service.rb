#!/usr/bin/env ruby
require File.join(File.dirname(__FILE__), '..', 'rds_backup_service')
require 'sinatra/base'
require 'fog_tracker'
require 'resque'

module RDSBackup
  # A RESTful web service for backing up RDS databases to S3.
  class Service < Sinatra::Base

    # check tmp/restart.txt for reload requests in development mode
    configure :development do
      require 'sinatra/reloader'
      register Sinatra::Reloader
    end

    # configure logging when not in test mode
    configure :production, :development do
      @logger = ::FogTracker.default_logger(STDOUT)
      @logger.level = ::Logger::INFO
      enable :logging
    end

    # on startup, load account information and start tracking RDS instances
    configure do
      @logger.info "Loading account information..."
      accounts = RDSBackup.read_rds_accounts
      tracker = FogTracker::Tracker.new(accounts, :logger => @logger)
      @logger.info "Starting tracker..."
      tracker.update
      tracker.start
      set :accounts, accounts
      set :tracker, tracker
    end

    before do ; content_type 'application/json' end   # serve JSON

    ######## POST /api/vXXX/backups ########
    # Queues a Job for a given :rds_instance
    post "#{RDSBackup.root}/backups" do
      rds_id  = params[:rds_instance]
      servers = settings.tracker['*::AWS::RDS::servers']
      rds     = (servers.select {|rds| rds.identity == rds_id}).first

      # check for errors
      if ! rds_id
        return [ 400, { errors: ["Parameter 'rds_instance' required"]}.to_json ]
      elsif ! (servers.map {|r| r.identity}).include?(rds_id)
        return [ 404, { errors: ["RDS instance #{rds_id} not found"]}.to_json ]
      end

      # request is OK - queue up a BackupJob
      job = Job.new(rds_id, rds.tracker_account[:name], params)
      logger.info "Queuing backup of RDS #{rds_id} in account #{job.account_name}"
      job.write_to_s3
      ::Resque.enqueue_to(:backups, Job, job.rds_id, job.account_name,
        params.merge(backup_id: job.backup_id, requested: job.requested))

      [ 201,                                # return HTTP_CREATED, and
        { 'Location' => job.status_url },   # point to the S3 document
        "#{job.to_json}\n"                  # and return the job as JSON
      ]
    end

    run! if app_file == $0  # start the server if ruby file executed directly
  end
end