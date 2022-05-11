#!/bin/bash
############################################################
# Backup script for MongoDB using mongodump and upload to
# either an AWS S3 bucket or Azure Blob container
#############################################################

# define the following variable in the .env file

# MONGO_URI => mongo host uri
# MONGO_USERNAME => username for mongodb
# MONGO_PASSWORD => password to authenticate against mongodb
# MONGO_AUTH_DB => name of mongo authentication database
# MONGO_SCOPE => scope of backup ([all] or [specific])
# MONGO_DB => specific mongo db to backup (optional)
# BACKUP_TARGET => sets target of [aws] s3 or [azure] blob
# AZURE_SAS_URI => azure SAS to blob container
# AWS_AUTH => sets auth type to [ec2] or [iam]
# AWS_REGION => sets the AWS region to use for S3 access
# AWS_S3_URI => aws s3 bucket name
# AWS_KEY => aws iam access key when [iam] auth type set
# AWS_SECRET => aws iam secret when [iam] auth type set
# FILE_PREFIX => backup file prefix name
# BACKUP_PATH => path for backups
# BACKUP_RETENTION => how long to keep backups

set -e

# load environment variables
source $HOME/mongo-backup.env

## Basic variable checking

# check the mongo uri
if [ -z "${MONGO_URI}" ]; then
  echo "Error: you must set the MONGO_URI environment variable"
  exit 1
fi

# check the mongo backup scope and database
if [ -z "${MONGO_SCOPE}" ]; then
  echo "Error: you must set the MONGO_SCOPE environment variable"
  exit 1
fi
if [ "${MONGO_SCOPE}" = "all" ]; then
  echo "MongoDB backup scope set to ALL databases"
fi
if [ "${MONGO_SCOPE}" = "specific" ]; then
  echo "MongoDB backup scope set to SPECIFIC"
  if [ -z "${MONGO_DB}" ]; then
    echo "Error: you must set the MONGO_DB environment variable when MONGO_SCOPE is set to SPECIFIC"
    exit 1
  else
    echo "The specific database to be backed up is ${MONGO_DB}"
  fi
fi

# check the mongo auth params
if [ -z "${MONGO_USERNAME}" ] || [ -z "${MONGO_PASSWORD}" ] || [ -z "${MONGO_AUTH_DB}" ]; then
  echo "Error: you must set all the MongoDB authentication environment variables"
  exit 1
fi

# check the Azure Blob container SAS URI
if [ "${BACKUP_TARGET}" = "azure" ]; then
  echo "Backup type is set to Azure Blob"
  if [ -z "${AZURE_SAS_URI}" ]; then
    echo "Error: you must set AZURE_SAS_URI"
    exit 1
  fi
fi

# check the S3 uri is set for either ec2 or iam auth type
if [ "${BACKUP_TARGET}" = "aws" ]; then
  echo "Backup type is set to AWS S3"
  if [ -z "${AWS_S3_URI}" ]; then
    echo "Error: you must set the AWS_S3_URI"
    exit 1
  elif [ -z "${AWS_REGION}" ]; then
    echo "Error: you must set the AWS_REGION"
    exit 1
  else
    echo "Setting AWS region to ${AWS_REGION}"
    export AWS_DEFAULT_REGION=${AWS_REGION}
  fi
fi
if [ "${AWS_AUTH}" = "iam" ]; then
  if [ -z "$AWS_KEY}" ] || [ -z "${AWS_SECRET}" ]; then
    echo "Error: you must set AWS_KEY and/or AWS_SECRET"
    exit 1
  else 
    echo "Setting AWS credentials"
    export AWS_ACCESS_KEY_ID=${AWS_KEY}
    export AWS_SECRET_ACCESS_KEY=${AWS_SECRET}
  fi
fi

# check the file/path variables are set
if [ -z "${FILE_PREFIX}" ]; then
  echo "Error: you must set a FILE_PREFIX for the backup"
  exit 1
fi
if [ -z "${BACKUP_PATH}" ]; then
  echo "Error: you must set a BACKUP_PATH for the backup"
  exit 1
fi
if [ -z "${BACKUP_RETENTION}" ]; then
  echo "Error: you must set a BACKUP_RETENTION for the backup"
  exit 1
fi

# set backup file format
BACKUP_FILE=${FILE_PREFIX}-$(date +%Y%m%d_%H%M%S).gz

# datestamp for backup 
echo "*** Backup Started ***"
date

# state backup scope for MongoDB and proceed with backup
if [ "${MONGO_SCOPE}" = "all" ]; then
  echo "Backing up ALL databases"
  echo "Dumping ALL databases to a compressed archive"
  mongodump ${MONGO_URI} -u ${MONGO_USERNAME} -p ${MONGO_PASSWORD} --authenticationDatabase=${MONGO_AUTH_DB} --archive=${BACKUP_PATH}/$BACKUP_FILE --gzip
  echo "Done!"
elif [ "${MONGO_SCOPE}" = "specific" ]; then
  echo "Backing up the ${MONGO_DB} database"
  echo "Dumping the ${MONGO_DB} database to a compressed archive"
  mongodump ${MONGO_URI} -u ${MONGO_USERNAME} -p ${MONGO_PASSWORD} --authenticationDatabase=${MONGO_AUTH_DB} --db=${MONGO_DB} --archive=${BACKUP_PATH}/$BACKUP_FILE --gzip
  echo "Done!"
fi

## AWS S3 or Azure Blob copy process - assumes validation done previously
if [ "${BACKUP_TARGET}" = "aws" ]; then
  echo "Using AWS S3 as the backup target"
  aws s3 cp ${BACKUP_PATH}/$BACKUP_FILE ${AWS_S3_URI}${BACKUP_FILE}
  echo "Done!"
elif [ "${BACKUP_TARGET}" = "azure" ]; then
  echo "Using Azure Blob as the backup target"
  azcopy cp ${BACKUP_PATH}/$BACKUP_FILE ${AZURE_SAS_URI}
  echo "Done!"
fi

# clean up local backup files based on retention
echo "Cleaning up local backups older than ${BACKUP_RETENTION} days"
find ${BACKUP_PATH} -mtime +${BACKUP_RETENTION} -type f -delete
echo "Backup Complete!"
exit 0
