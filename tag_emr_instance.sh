#!/bin/bash
#
# tag_emr_instance.sh
#
# Simple script to tag EMR clusters and their EC2 instances from the instances
# themselves. Can (and should) be used as a bootstrap action.

# For EMR tagging to work the cluster should have been created with "visible
# to all IAM users" set as true or the same credentials used to create the
# cluster must be provided with --aws-credentials.
#
# Usage:
#
#   tag_emr_instance.sh [--aws-credentials=S3_PATH] TAG_NAME[=TAG_VALUE] TAG...
#
# Copyright (C) 2013 Tiago Alves Macambira <macambira (@) chaordicsystems.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.


set -e  # abort execution on errors
set -x  # print what is happening
set -o nounset  # using unset variabled will case script to fail and abort


# Create a separate dir to hold our junk
INSTALL_DIR=tag_emr_instance
mkdir --parent ${INSTALL_DIR}
cd ${INSTALL_DIR}


# Command line parsing ################################################
#
#
# Try to download AWS credentials, if instructed to do so. Otherwise we will
# use credentials provided by the environment.
#
# Aditional arguments will be used as tags to ec2-create-tags.
TAG_ARGS=""
for tag in "$@" ; do
    case $tag in
        --aws-credentials=s3*)
            AWS_CREDENTIALS_URL=$(echo $tag | cut -d= -f2)
            hadoop dfs -get "${AWS_CREDENTIALS_URL}" credentials.sh
            source credentials.sh
            rm credentials.sh
            ;;
        *)
            TAG_ARGS="${TAG_ARGS} --tag ${tag}"
            ;;
    esac
done


set +o nounset  # disable unset errors
if [ -z "${AWS_ACCESS_KEY}" -o -z "${AWS_SECRET_KEY}" ]; then
    echo "AWS access credentials not found. Aborting." > /dev/stderr
    exit 1;
fi
if [ -z "${TAG_ARGS}" ]; then
    echo "No tag provided. Aborting." > /dev/stderr
    exit 1;
fi
set -o nounset  # using unset variabled will case script to fail and abort


# Instance meta-data retrieval ########################################
#
#
# Retrieve currently running EMR's instance instanceID using Amazon's
# Instance Metadata Service
INSTANCE_ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)

# Retrieve currently running EMR's instance availability zone using Amazon's
# Instance Metadata Service
# Reference: http://aws.amazon.com/code/1825
AVAILABILITY_ZONE=$(wget -q -O - http://169.254.169.254/latest/meta-data/placement/availability-zone)

# Deduce region from availability zone.
# Reference: http://stackoverflow.com/questions/4249488/find-region-from-within-ec2-instance
REGION=$(echo ${AVAILABILITY_ZONE} | sed -e 's:\([0-9][0-9]*\)[a-z]*$:\1:')


# EC2 tagging #########################################################
#
#
# Download and install Amazon EC2 CLI tools
wget 'http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip'
unzip ec2-api-tools.zip
export EC2_HOME=$(find $(pwd) -type d -name 'ec2-api-tools-*' | tail -1)
EC2_CREATE_TAGS="${EC2_HOME}/bin/ec2-create-tags"
chmod 755 $EC2_CREATE_TAGS


# Finally, call ec2-create-tags with the argument list constructed during
# command line parsing.
$EC2_CREATE_TAGS --region=${REGION} ${INSTANCE_ID} $TAG_ARGS


# EMR cluster tagging #################################################
#
#
# EMR tagging will only be performed once...
# ... if and only if we are running inside a EMR cluster and...
# (reference: http://docs.aws.amazon.com/ElasticMapReduce/latest/DeveloperGuide/Config_JSON.html)
export EMR_JSON_INFO_HOME='/mnt/var/lib/info'
export EMR_JOB_INFO_FILE="${EMR_JSON_INFO_HOME}/job-flow.json"
export EMR_INSTANCE_INFO_FILE="${EMR_JSON_INFO_HOME}/instance.json"
if ! [ -r ${EMR_INSTANCE_INFO_FILE} -a -r ${EMR_JOB_INFO_FILE} ]; then
    echo "It does not seem we are running inside a EMR Hadoop cluster node."
    echo "Nothing left to tag. Exiting without failures."
    exit 0
fi
# ... IFF we are running in the master node the master node
if ! (python -c 'import json; import sys; assert json.load(open("'${EMR_INSTANCE_INFO_FILE}'"))["isMaster"];sys.exit(0);' &> /dev/null ); then
    echo "It does not seem we are running in the master EMR node."
    echo "Nothing left to tag. Exiting without failures."
    exit 0
fi

# We are good to go.
# Discover current jobflow's id
JOB_FLOW_ID=$(python -c 'import json; import sys; print json.load(open("'${EMR_JOB_INFO_FILE}'"))["jobFlowId"];')

# Download and install Amazon EMR CLI tool
wget 'http://elasticmapreduce.s3.amazonaws.com/elastic-mapreduce-ruby.zip'
export EMR_CLI_HOME=$(pwd)/'elastic-mapreduce-cli'
unzip elastic-mapreduce-ruby.zip -d ${EMR_CLI_HOME}
EMR_CLI_TOOL="${EMR_CLI_HOME}/elastic-mapreduce"
chmod 755 ${EMR_CLI_TOOL}
EMR_CLI_CREDENTIALS=${EMR_CLI_HOME}/credentials.json

# Setup credentials for Amazon EMR CLI tool
cat << EOF_CREDENTIALS > ${EMR_CLI_CREDENTIALS}
{
"access_id": "${AWS_ACCESS_KEY}",
"private_key": "${AWS_SECRET_KEY}",
"region": "${REGION}"
}
EOF_CREDENTIALS

# Finally, call Amazon EMR CLI tool with the argument list constructed during
# command line parsing.
${EMR_CLI_TOOL} --credentials=${EMR_CLI_CREDENTIALS} \
                --region=${REGION} \
                --jobflow ${JOB_FLOW_ID} \
                --add-tags $TAG_ARGS

# And we are done. :)
exit 0
