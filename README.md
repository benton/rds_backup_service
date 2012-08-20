RDS Dump Service 
================
Fire-and-forget backups of Amazon Web Services' RDS databases into S3.

----------------
What is it?
----------------
A REST-style web service for safely dumping contents of a live AWS 
Relational Database Service instance into a compressed SQL file.

----------------
Why is it?
----------------


----------------
Installation
----------------
The RDS Dump Service can be used as a standalone application or as a Rack 
middleware library.

###   To install as an application  ###

Install project dependencies, fetch the code, and 

    gem install rake bundler
    git clone https://github.com/benton/cloud_financial_officer.git
    cd rds_dump_service
    bundle

###   To install as a library   ###

  1) Install the gem, or add it as a Bundler dependency and `bundle`.

        gem install rds_dump_service

  2) Require the middleware from your Rack application, then insert it
    in the stack:

        require 'rds_dump_service'
        ...
        config.middleware.use RDSDumper::Service  # (Rails application.rb)
                                                  # or
        use RDSDump::Service                      # (Sinatra)


----------------
Usage
----------------
The service is run with:

      rake service
or

      bundle exec rackup

The entry point for the REST API is `/api/v1/backups`
(See the {file:API.md API documentation})


----------------
Development
----------------

*Getting started with development*

1) Install project dependencies

    gem install rake bundler

2) Fetch the project code

    git clone https://github.com/benton/rds_dump_service.git
    cd rds_dump_service

3) Bundle up and run the tests

    bundle && rake

