#!/bin/bash
#
# tag_emr_instance.sh
#
# Simple script to tag EMR instances from the instance itself.
# Can (and should) be used as a bootstrap action
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

# Command line parsing
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

# Download and install Amazon CLI tools
wget 'http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip'
unzip ec2-api-tools.zip
export EC2_HOME=$(find $(pwd) -type d -name 'ec2-api-tools-*' | tail -1)
EC2_CREATE_TAGS="${EC2_HOME}/bin/ec2-create-tags"
chmod 755 $EC2_CREATE_TAGS

# Retrieve currently running EMR's instance instanceID using Amazon's
# Instance Metadata Service
INSTANCE_ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)

# Split a internal hostname like ip-10-44-191-108.eu-west-1.compute.internal
# to figure out the region of this instance.
REGION=$(hostname | cut -d. -f2)

# Finally, call ec2-create-tags with the argument list constructed during
# command line parsing.
$EC2_CREATE_TAGS --region $REGION $INSTANCE_ID $TAG_ARGS
