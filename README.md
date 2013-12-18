Usage
=====

    tag_emr_instance.sh [--aws-credentials=S3_PATH] TAG_NAME[=TAG_VALUE] TAG...

What
====

This is a short script that, once ran from inside a running EMR/EC2
instance, it will [tag][] this instance with the provided tags and, when
executed from a master node in a EMR cluster, [tag the whole EMR
cluster][emr-tag] as well.

If used as a [bootstrap action][], which is actually the original purpose of
this script, resource (instance) tagging becomes a more robust and
passive process: every EMR instance created will apply its tags during
initialization -- or just fail and thus abort its initialization.

Contrasting with a reactive approach, where a process monitors the list
of created Elastic MapReduce jobflows, enumerates its instances and then
tags those instances, the "bootstrap action approach" is supposedly more
robust as every running instance **was** tagged before it became
operational.

Another nice thing about doing tagging as a [bootstrap action][] is that it
decouples tagging support from the underlying framework used with EMR:
be it a JAR application, a Streaming application, a MrJob script or
whatever, it will Just Work &copy;.

Contents
========

* `tag_emr_instance.sh`, our bootstrap script.
* `credentials.sh`, a sample  _credentials_ script. More about it later.

How
===

Add the following [bootstrap action][] to your EMR job description:

* **Name:** TagInstances
* **Path (to script):** `s3://engine-data/data/bootstrap-actions/tag_emr_instance.sh`
* **Arguments:** `--aws-credentials=s3://engine-data/credentials/aws_credentials.sh team=recsys env=dev`

Enjoy. :)

For instance, to add such [bootstrap action][] to a MrJob script, just follow the example bellow:

    runners:
        emr:
            bootstrap_actions:
            - s3://elasticmapreduce/bootstrap-actions/configurations/latest/memory-intensive
            - s3://engine-data/data/bootstrap-actions/tag_emr_instance.sh --aws-credentials=s3://engine-data/credentials/aws_credentials.sh team=a-team cost-center=FMI


Notice:

* Tags are provided as arguments to this [bootstrap action][].
* The option `--aws-credentials` is used to provide the path to a script
  in S3 from where AWS access credentials will be read.
* For EMR tagging to work the cluster should have been created with ["visible
  to all users"][visibility] set as true. Another option is to have the same
  credentials used to create the cluster provided with --aws-credentials.


AWS credentials and security considerations
===========================================

Internally, this script executes some EC2 and EMR scripts that require access
to Amazon Web Services credentials (AWS_ACCESS_KEY, AWS_SECRET_KEY) being
available as environment variables at execution time.

Given that bootstrap scripts must be publicly accessible files in S3, it
seems unwise to store your AWS credentials hard coded in it. It would be
wiser to store it in a separate  path/file accessible only from
authorized instances -- i.e., any non-public file in S3 bucket you have
access. During `tag_emr_instance.sh` execution, it will download this
credentials file, whose path should be provided using the
`--aws-credentials`, and use AWS credentials stored in it.

The minimal required action for this script to work is "ec2:CreateTags",
so the following would be a usable IAM policy for a user who's only purpose
it is to tag EMR instances:

    {
      "Statement": [
        {
          "Action": "ec2:CreateTags",
          "Effect": "Allow",
          "Resource": "*"
        }
      ]
    }

 *Untested* To be able to tag the EMR cluster (not instances), a similar policy, related to EMR, should be usable for the proveided credentials/IAM user as well.


Bellow, there is an example of a credentials file  as expected by
`tag_emr_instance.sh`:

    #!/bin/bash

    set -e

    export AWS_ACCESS_KEY='blablalbabla'
    export AWS_SECRET_KEY='yadayadayada'

A similar file is provided as `credentials.sh` file in
`tag_emr_instance.sh` distribution.

A default path for this bootstrap action is not left with a default
value for the same reasons we avoid storing AWS credentials hard coded
into the `tag_emr_instance.sh` script itself.

Perhaps there are better and more secure ways if forwarding a AWS
credential to a bootstrap action script. Comments and suggestions are
welcome.


License and code location
=========================

This code is licensed under a MIT License and hosted in
https://github.com/chaordic/tag-emr-instance.



[tag]: http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html (Tagging Your EC2 Resources)

[bootstrap action]: http://docs.aws.amazon.com/ElasticMapReduce/latest/DeveloperGuide/Bootstrap.html (Bootstrap Actions)

[Instance Metadata Service]: http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AESDG-chapter-instancedata.html

[emr-tag]: http://docs.aws.amazon.com/ElasticMapReduce/latest/DeveloperGuide/emr-plan-tags.html

[visibility]: https://docs.aws.amazon.com/ElasticMapReduce/latest/DeveloperGuide/emr-plan-access-iam.html