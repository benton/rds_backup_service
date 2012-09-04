RDS Backup Service
================
Fire-and-forget SQL backups of Amazon Web Services' RDS databases into S3.

----------------
What is it?
----------------
A REST-style web service and middleware library for safely dumping the contents
of a live AWS Relational Database Service instance into a compressed SQL file.

The service has only one API call (a POST to `/api/v1/backups`), which spawns
a long-running worker process. The worker performs the following steps:

1. Snapshots the original RDS
2. Creates a new RDS instance based on the snapshot
3. Configures the new RDS as needed, including rebooting for Parameter Group
4. Connects to the RDS and dumps the database contents, compressing on the fly
5. Uploads the compressed SQL file to S3, and optionally emails its URL
6. Deletes up the snapshot, temporary instance, and local SQL dump

----------------
Why is it?
----------------
Safely and consistently grabbing the contents of a loaded, live RDS instance
is a pain (if it has no existing slave). Though the steps are simple, they're
brittle, slow, and involve lots of waiting for indeterminate time periods.

----------------
Installation
----------------
First install the dependencies:

* Ruby 1.9, rake, and bundler
* [Redis][] (for [Resque][] workers), or [DelayedJob][] (library only for now)
* mysqldump
* gzip

The RDS Backup Service can be installed as a standalone application or as a
Rack middleware library.

###   To install as an application  ###

Install project dependencies, fetch the code, and bundle up.

    gem install rake bundler
    git clone https://github.com/benton/rds_backup_service.git
    cd rds_backup_service
    bundle

###   To install as a library   ###

1) Install the gem, or add it as a Bundler dependency and `bundle`.

      gem install rds_backup_service

2) Require the middleware from your Rack application, then insert it
  in the stack:

      require 'rds_backup_service'
      ...
      config.middleware.use RDSBackup::Service  # (Rails application.rb)
                                                # or
      use RDSBackup::Service                    # (Sinatra)

3) If desired, require the SecurityGroup setup task in your `Rakefile`:

      require 'rds_backup_service/tasks'

----------------
Configuration and Setup
----------------
Two configuration files are required _(see included examples)_:

* `./config/accounts.yml` or `ENV['RDS_ACCOUNTS_FILE']`

  This file defines three different types of AWS accounts: the various RDS
  accounts to grab SQL from; the S3 account where the SQL output
  will be written; and an optional EC2 account, which is used by the
  `setup:rds_backup_groups` rake task to perform post-configuration setup.

* `./config/settings.yml` or `ENV['RDS_SETTINGS_FILE']`

  This file defines the S3 bucket name for the output, plus some other options.

Once these files have been edited, run `rake setup:rds_backup_groups`, which:

* makes sure the configured Security Groups exist in all the RDS and EC2 accounts
* opens the RDS Security Group in each RDS account to the EC2 Security Group
* checks to see that the current host is in the EC2 Security Group (when in EC2)

----------------
Usage
----------------
The service is run in the standard Rack manner:

    bundle exec rackup

The entry point for the REST API is `/api/v1/backups`
(See the {file:API.md API documentation})

The Resque workers are run with:

    QUEUE=backups rake resque:work


----------------
DelayedJob
----------------
The library (though not the service) can be used with DelayedJob.
Place some code like this in your Controller or Model:

    require 'rds_backup_service'
    ...
    job = RDSBackup::Job.new(params[:rds_id])
    job.write_to_s3
    Delayed::Job.enqueue RDSBackup::DelayedJob.new(job.rds_id, {
        backup_id: job.backup_id,
        requested: job.requested.to_s,
        email:     params[:email],
      })



[Redis]: http://redis.io/
[Resque]: https://github.com/defunkt/resque
[DelayedJob]: https://github.com/collectiveidea/delayed_job

