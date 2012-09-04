RDS Backup Service REST API
================
The REST API exposes only one API call:

    POST /api/v1/backups

POST to here with parameter `rds_instance` set to an RDS instance name.

----------------
Backups
----------------
A Backup represents a long-running backup process for an RDS.

**RESOURCE LOCATION**: `/api/v1/backups`

**REQUEST PARAMETERS**:

  * rds_instance:   the name of the RDS instance to dump to S3 - **REQUIRED**
  * email:          an optional email address to send a message to on completion
  

**RESULT FIELDS**:

  * rds_instance:   the name of the RDS instance being dumped to S3
  * account_name:   the name of account from accounts.yml, if determined
  * backup_status:  an HTTP-like status code for the process
  * status_url:     a signed S3 URL to this job's JSON status as updated
  * status_message: a descriptive progress message
  * files:          an Array of output files for this job, including S3 URLs
