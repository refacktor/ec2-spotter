AMI Tools
---------

An Amazon Machine Image (AMI) is a file system image that can be
mounted as a loopback device and then used as a file system for a
Virtual Machine Instance.

The AMI Tools are a set of command line utilities for creating,
bundling and uploading AMIs to S3 storage where they can be used by
EC2.

The following user command line tools are provided:

- ec2-bundle-image:      bundle an existing AMI
- ec2-bundle-vol:        create an AMI from an existing installation
                         volume and bundle it
- ec2-upload-bundle:     upload a bundled AMI to S3 storage
- ec2-delete-bundle:     delete a bundled AMI stored in S3
- ec2-download-bundle:   download an existing bundle
- ec2-unbundle:          extract a loopback filesystem from an
                         existing bundle
- ec2-migrate-manifest:  modify a manifest file for use in a
                         different region
- ec2-migrate-bundle:    modify and copy an existing bundle for use
                         in a different region


Compatability
-------------

The AMI Tools are available in a self contained zip file for systems
that do not support RPMs. They should run on most Linux distributions
provided the following dependencies are installed and available from
the current search path:
	- curl
	- gzip
	- mkfifo
	- openssl
	- rsync
	- Ruby 1.8.2 or later
	- tee

All utilies should work across Linux distributions provided the above
dependencies are met.

Installation
------------

To install the AMI Tools unzip the installation file into a suitable
installation directory such as '/usr/local':

	unzip ec2-ami-tools-X.X-XXXX.zip -d <installation-dir>

This will create the directory

     '<installation-dir>/ec2-ami-tools-X.X-XXXX' 

where X.X-XXXX represents the release and build numbers.

Before running the utilities the EC2_HOME environment variable
needs to be set:

	export EC2_HOME=<installation-dir>/ec2-ami-tools-X.X-XXXX

If you are using the EC2 API tools and cannot, or would rather not,
allow them to share a home directory you can set an EC2_AMITOOL_HOME
environment variable instead. This variable takes precedence if both
are set.

	export EC2_AMITOOL_HOME=<installation-dir>/ec2-ami-tools-X.X-XXXX

The utilities can also be added to the path:

	export PATH=$PATH:${EC2_AMITOOL_HOME:-EC2_HOME}/bin

Documentation
-------------

The manual for each utility can be displayed by invoking it with the
--manual parameter. For example:

	ec2-bundle-image --manual

The help for each utility can be displayed by invoking it with the
--help parameter. For example:

	ec2-bundle-image --help


X.509 Certificates
------------------

Two X.509 certificates are required: one for EC2 and one for the user.
The X.509 certificates used by the AMI Tools must be X.509
certificates and, like the private key files, must be PEM encoded.

The EC2 X.509 certificate is located at:

 <installation-dir>/ec2-ami-tools-X.X-XXXX/etc/ec2/amitools/cert-ec2.pem
