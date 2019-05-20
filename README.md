aws-hosting
===========

A solution to deploy a classic web hosting platform into AWS Cloud.  The
solution configures an AWS CloudFormation stack that is self-sufficient and
self-managed.  As such it has an integrated CI/CD based on AWS CodeCommit,
AWS CodePipeline, and AWS CodeBuild.  This CI/CD environment is used to
apply runtime changes to the corresponding stack for the lifetime of the
platform.

The solution is highly configurable and can accomodate a range of requirements
expected from a properly designed web hosting platform.

Deploying the solution
----------------------

### Prerequisites

* a working AWS CLI tools (you should be able to execute `aws s3 ls` and see no
  error)
* a defined SSH keypair in EC2 in the region you are going to deploy the solution
* the AWS region should support SimpleAD as a backend for the AWS Directory
  Service (or you can modify the stack to use the directory service backed by
  MS Active Directory, if money is not an issue for you)

To instantiate a web hosting platform the following steps are required:

> Replace __<STACK_NAME>__ with the desired name of the stack, e.g. "hosting"

1. Clone this repository to a local folder on your computer

       git clone https://github.com/openwall-com-au/aws-hosting

2. Change directory to the cloned folder

       cd aws-hosting

3. Adjust the local settings of the repository so it would play nice with AWS
   CodeCommit.

       git config --local credential.helper '!aws codecommit credential-helper "$@"'
       git config --local credential.UseHttpPath True

   Alternately, you can add the following snippet to your `~/.gitconfig` file:
   > Replace __<AWS_REGION>__ with the AWS Region you work with, e.g. us-west-2

       [credential "https://git-codecommit.<AWS_REGION>.amazonaws.com"]
           helper = !aws codecommit credential-helper $@
           UseHttpPath = True

4. Deploy the loader stack first.  The stack will create an AWS S3 bucket and
   an AWS CodeCommit repository.

       aws cloudformation deploy --template-file bootstrap/templates/loader.template --stack-name <STACK_NAME>
 
5. Retrieve the output of the recently deployed stack to get the name of the
   bucket and the URL of the repository.

       aws describe-stacks --stack-name next --query 'Stacks[0].Outputs[?OutputKey == `ArtifactStore` || OutputKey == `RepositoryUrl`][OutputKey, OutputValue]' --output text --stack-name <STACK_NAME>
 
   This will produce output like the following:
   
       ArtifactStore	<STACK_NAME>-artifactstore-XXXXXXXXXXXXX
       RepositoryUrl	https://git-codecommit.<AWS_REGION>.amazonaws.com/v1/repos/<STACK_NAME>

6. Prepare and push the repository to the AWS CodeCommit repository.

   > Replace __<REPOSITORY_NAME>__ with the value you retrieve in the previous
     step

       git subtree split --prefix infrastructure -b infrastructure
       git subtree split --prefix images -b images
       git push --mirror <REPOSITORY_URL>
       aws codecommit update-default-branch --default-branch-name master --repository-name <STACK_NAME>

7. Prepare the primary stack for the bootstrapping.  This will adjust the
   integrated CI/CD to use the bootstrap directory for the initial pass of the
   AWS CodeBuild project.

       sed 's/^\(\([[:space:]]*\)BranchName:\) infrastructure/\1 master\n\2BuildSpec: bootstrap\/buildspec.yml\n\2PrivilegedMode: true/' infrastructure/templates/infrastructure.template > infrastructure/templates/bootstrap.template 

8. Package and deploy the bootstrapping stack.

   > Replace __<S3_BUCKET>__ with the value you retrieved for the `ArtifactStore`
     in step 5
   
   > Replace __<KEYNAME>__ with the name of the EC2 SSH key which is already
     defined in the selected AWS region
  
   > The following example deploys the stack to use 2 availability zones and
     specifies which zones to pick, but please check the Parameters section of the
     [infrastructure.template](infrastructure/templates/infrastructure.template)
     to see what parameters you can configure.  All parameters are optional, but
     ommitting some may produce less functional platform, e.g. if you skip the
    ` DatabaseEngine` parameter there will be no RDS backend created.

       aws cloudformation package --template-file infrastructure/templates/bootstrap.template --output-template-file bootstrap.template.packaged --s3-prefix cloudformation --s3-bucket <S3_BUCKET>
       aws cloudformation deploy --template-file bootstrap.template.packaged --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND --stack-name <STACK_NAME> --parameter-overrides DatabaseEngine=postgres KeyName=<KEYNAME> AvailabilityZones=<AWS_REGION>a,<AWS_REGION>b AvailabilityZonesCount=2 Encryption=custom-key --s3-bucket <S3_BUCKET>

9. Take a break and drink some coffee since it would take approximately 30-40
   minutes to deploy.  You can monitor the progress in the AWS CloudFormation
   and also in the AWS CodePipeline consoles.

10. If everything is completed without issues and the status for all nested
    stacks starting with the <STACK_NAME> prefix is 'UPDATE_COMPLETED' you can
    test that the stack is working by executing the following commands:

        ENDPOINT=$(aws cloudformation describe-stacks --stack-name n3 --query 'Stacks[0].Outputs[?OutputKey == `DNSName`][OutputValue]' --output text)
        curl "$ENDPOINT/healthcheck"         # this tests nginx and static content service
        curl "$ENDPOINT/healthcheck/php-fpm" # this tests PHP/FPM and dynamic content service
    
    An example session is shown below:

        [galaxy@intruder aws-hosting]$ ENDPOINT=$(aws cloudformation describe-stacks --query 'Stacks[0].Outputs[?OutputKey == `DNSName`][OutputValue]' --output text --stack-name hosting)
        [galaxy@intruder aws-hosting]$ echo "$ENDPOINT"
        hosting-WebLoadB-GZHUZTDEFA04-520656215.us-west-2.elb.amazonaws.com
        [galaxy@intruder aws-hosting]$ curl "$ENDPOINT/healthcheck"
        OK Host="ip-10-0-3-14.id.hosting.internal" Date="Monday, 20-May-2019 12:27:17 UTC" Time="20/May/2019:12:27:17 +0000"
        [galaxy@intruder aws-hosting]$ curl "$ENDPOINT/healthcheck/php-fpm" ; echo
        OK Pool="www"
        [galaxy@intruder aws-hosting]$

The stack is now fully deployed and is ready to be used.

Logging into the EC2 instances
------------------------------

The stack deploys at least 3 type of instances: bastion, web, and application.
SSH access to web and application instances is only allowed from the bastion
instance.  To access the bastion instance you need to add your IP address to
the `ssh` Security Group associated with the VPC of the deployed stack.  Once
it is done, you can login to the bastion instance using the following command:

    ssh -i /path/to/your/private/key r_admin@<public_IP_of_the_bastion_instance>

To access the web and application instances it is recommended to use SSH
port-forwarding (a convenient configuration to be able transparently leverage
that is described in [this blog post](https://dmitry.khlebnikov.net/2015/08/transparent-ssh-host-jumping-advanced.html).

Customising the platform
------------------------

By default the stack is using only upstream packages from CentOS and EPEL
repositories.  The idea is that you should treat the solution as a black box
or, if you like this analogy better, a platform you build upon.  The
recommended way to build upon this stack is to clone the deployed repository
and apply your changes there.

You can get the repository URL with the following command:

    aws describe-stacks --query 'Stacks[0].Outputs[?OutputKey == `RepositoryUrl`][OutputValue]' --output text --stack-name <STACK_NAME>

The repository contains three branches: master, images, and infrastructure .

The master branch represents the entire solution and will match the upstream
repository you deployed.  You should not touch that branch since the only time
it is supposed to be updated is when you get an update from the upstream and
you want to apply these changes to the already deployed stack.

The infrastructure branch is responsible for any adjustments you may want to
introduce to the infrastructure layout of the deployed stack, e.g. if you want
to create, say, an ElasticSearch cluster or any other resource not provided by
the solution you do it by modifying and committing your change to this branch.

The images branch holds the bootstrapping information for all EC2 instances in
the solution.  Most likely, this is the branch you will modify the most.

So, how the customisation workflow looks like?  Pretty simple.  You deploy the
solution as was described above and, once you confirm that the deployment went
successful, you clone the desired branch from the deployed AWS CodeCommit
repository to a dedicated folder.  The following is an example session output:

    [galaxy@intruder ~]$ git clone -b images --depth 1 https://git-codecommit.us-west-2.amazonaws.com/v1/repos/hosting images
    Cloning into 'images'...
    remote: Counting objects: 26, done.
    Unpacking objects: 100% (26/26), done.
    [galaxy@intruder ~]$ cd images
    [galaxy@intruder images]$ ls -l
    total 20
    drwxr-xr-x 3 galaxy galaxy 4096 May 20 22:58 auto
    -rw-r--r-- 1 galaxy galaxy  166 May 20 22:58 buildspec.yml
    -rw-r--r-- 1 galaxy galaxy   28 May 20 22:58 README.md
    drwxr-xr-x 2 galaxy galaxy 4096 May 20 22:58 scripts
    drwxr-xr-x 3 galaxy galaxy 4096 May 20 22:58 templates
    [galaxy@intruder images]$

Once the branch was cloned into the dedicated folder you may apply your changes
there.  Once you are satisfied you need to push it back.  The following show
cases how the platform was customised to use PHP 5.5 from Remi's repository and
some adjustments to the SELinux configuration in the application instances:

    [galaxy@intruder images]$ git config --local user.email 'galaxy@hosting'
    [galaxy@intruder images]$ git config --local user.name '(GalaxyMaster)'
    [galaxy@intruder images]$ git diff
    diff --git a/scripts/app.userdata b/scripts/app.userdata
    index 7799db1..65b3dbb 100644
    --- a/scripts/app.userdata
    +++ b/scripts/app.userdata
    @@ -21,8 +21,10 @@ safe_yum()
     [ -e "$BOOTSTRAP_MNT"/etc/resolv.conf -o -h "$BOOTSTRAP_MNT"/etc/resolv.conf ] \
     	&& mv -f "$BOOTSTRAP_MNT"/etc/resolv.conf{,.preserved} ||:
     cp -aL /etc/resolv.conf "$BOOTSTRAP_MNT"/etc/resolv.conf
    -safe_yum install epel-release chrony postfix cachefilesd sudo
    -safe_yum install nfs-utils adcli authconfig sssd-ad haveged fcgi awscli \
    +safe_yum install epel-release https://rpms.remirepo.net/enterprise/remi-release-7.rpm
    +safe_yum install --enablerepo=remi-php55 \
    +	chrony postfix cachefilesd sudo \
    +	nfs-utils adcli authconfig sssd-ad haveged fcgi awscli \
     	php-{cli,fpm,gd,mbstring,mcrypt,pdo,pear,pecl-{igbinary,lzf,redis,zendopcache},pgsql,process,soap,xml} \
     	postgresql
     safe_yum install https://github.com/openwall-com-au/fcgi-multiplexer/releases/download/0.0.1/fcgi-multiplexer-0.0.1-1.noarch.rpm
    @@ -401,6 +403,9 @@ chown -h root:root "$BOOTSTRAP_MNT"/root/bootstrap.d/*.sh
     chroot "$BOOTSTRAP_MNT" /bin/sh -exuc "\
     	semanage boolean -N --modify --on use_nfs_home_dirs
     	semanage boolean -N --modify --on httpd_use_nfs
    +	semanage boolean -N --modify --on httpd_can_network_connect_db
    +	semanage boolean -N --modify --on httpd_can_connect_ldap
    +	semanage boolean -N --modify --on httpd_can_sendmail
    
     	semanage fcontext -a -e /etc /usr/share/etc
     	mkdir -m0755 /usr/share/etc
    
    [galaxy@intruder images]$ git add scripts/app.userdata
    [galaxy@intruder images]$ git commit -m 'Replaced PHP54 with Remi PHP55'
    [images 2565a70] Replaced PHP54 with Remi PHP55
     1 file changed, 7 insertions(+), 2 deletions(-)
    [galaxy@intruder images]$ git push
    Enumerating objects: 7, done.
    Counting objects: 100% (7/7), done.
    Delta compression using up to 4 threads
    Compressing objects: 100% (4/4), done.
    Writing objects: 100% (4/4), 545 bytes | 545.00 KiB/s, done.
    Total 4 (delta 2), reused 0 (delta 0)
    To https://git-codecommit.us-west-2.amazonaws.com/v1/repos/hosting
       904030c..2565a70  images -> images
    [galaxy@intruder images]$

That is it!  You can monitor your changes being propagated in the AWS
CodePipeline console in the AmiCreator pipeline.  If the pipeline fails for any
reason you should be able to see the logs and adjust your changes, push another
commit, etc. until the pipeline completes successfully.  Once it does your
changes are live!

The same approach could be applied to the infrastructure branch, but there are
some dragons down there which I will document as time permits.  The most
painful one is when you try to introduce a new item into the IAM policy.  The
recommended approach is to work in stages: first introduce the new IAM policy
item, push the change and wait while it successfully propagates, then create
the resource and push the change.  Keep in mind that you should always test the
changes to the infrastructure branch on a separate deployment of the solution
since a mistake in that branch may render the stack to be broken with no
rollback or recovery option.
