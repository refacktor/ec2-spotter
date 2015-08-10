# ec2-spotter

EC2-Spotter is a utility for running Spot Instances on persistent EBS root volumes.

It is based initially on the article found here:
http://www.bluegecko.net/amazon-web-services/ec2-persistent-boots-with-pivot-root/

The article was outdated so a lot of changes are needed.

Currently this is Work In Progress.

As of 08/09/2015 there is an error in make-ec2-image.sh:

```
Bundling image file...
Splitting /tmp/busybox.fs.tar.gz.enc...
Created busybox.fs.part.0
Generating digests for each part...
Digests generated.
Creating bundle manifest...
Bundle manifest is /tmp/busybox.fs.manifest.xml
ec2-bundle-image complete.
#18. Upload the image.
Signature version 4 authentication failed, trying different signature version
ERROR: Error talking to S3: Server.NotImplemented(501): A header you provided implies functionality that is not implemented
```
