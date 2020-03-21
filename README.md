# packer-centos8-ami

Packer template for building a clean CentOS 8 AWS AMI
Example to run:
```shell script
$ AWS_PROFILE=test packer build template.json
...
==> Builds finished. The artifacts of successful builds are:
--> amazon-ebssurrogate: AMIs were created:
us-east-1: ami-023307779aa11db48
```

