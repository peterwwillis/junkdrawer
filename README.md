Table of Contents
 * [ad-ldap-tool.sh - Search Microsoft Active Directory using ldapsearch](#ad-ldap-toolsh---search-microsoft-active-directory-using-ldapsearch)
 * [apt-update-security-packages.sh - Update Apt packages for security updates](#apt-update-security-packagessh---update-apt-packages-for-security-updates)
 * [aws-adfs-profile-login - Login to AWS with aws-adfs, using AWS profiles](#aws-adfs-profile-login---login-to-aws-with-aws-adfs-using-aws-profiles)
 * [aws-assume-admin-role - Assume an admin role and execute arbitrary commands](#aws-assume-admin-role---assume-an-admin-role-and-execute-arbitrary-commands)
 * [aws-assume-role - A wrapper to make it easier to assume AWS roles](#aws-assume-role---a-wrapper-to-make-it-easier-to-assume-aws-roles)
 * [aws-cli-cache-auth-keys.sh - Extract the auth keys from a cached AWS CLI authentication json file](#aws-cli-cache-auth-keyssh---extract-the-auth-keys-from-a-cached-aws-cli-authentication-json-file)
 * [aws-create-update-secret - Create or update an AWS Secrets Manager secret](#aws-create-update-secret---create-or-update-an-aws-secrets-manager-secret)
 * [aws-ec2-describe-sec-group-rules.sh - Print a TSV of AWS EC2 security group rules](#aws-ec2-describe-sec-group-rulessh---print-a-tsv-of-aws-ec2-security-group-rules)
 * [aws-ec2-get-instance-id.sh - Get the Instance ID of running AWS EC2 instances](#aws-ec2-get-instance-idsh---get-the-instance-id-of-running-aws-ec2-instances)
 * [aws-ec2-get-ip.sh - Get the IPs of running AWS EC2 instances](#aws-ec2-get-ipsh---get-the-ips-of-running-aws-ec2-instances)
 * [aws-ec2-get-network-interface-public-ips.sh - Get the public IP of AWS EC2 network interfaces](#aws-ec2-get-network-interface-public-ipssh---get-the-public-ip-of-aws-ec2-network-interfaces)
 * [aws-ec2-get-running-instances.sh - Get the Instance ID, key name, group ID, and public IP of running AWS EC2 instances](#aws-ec2-get-running-instancessh---get-the-instance-id-key-name-group-id-and-public-ip-of-running-aws-ec2-instances)
 * [aws-ec2-get-security-groups.sh - Get AWS EC2 security groups](#aws-ec2-get-security-groupssh---get-aws-ec2-security-groups)
 * [aws-ec2-get-sg-ids.sh - Get AWS EC2 instance security group IDs](#aws-ec2-get-sg-idssh---get-aws-ec2-instance-security-group-ids)
 * [aws-ecr-create-repository - Create an AWS ECR repository](#aws-ecr-create-repository---create-an-aws-ecr-repository)
 * [aws-ecr-docker-login - Perform a Docker login to an AWS ECR repository](#aws-ecr-docker-login---perform-a-docker-login-to-an-aws-ecr-repository)
 * [aws-ecr-docker-pull - Pull a Docker image from an AWS ECR registry](#aws-ecr-docker-pull---pull-a-docker-image-from-an-aws-ecr-registry)
 * [aws-ecr-docker-push - Push a Docker container to an AWS ECR registry](#aws-ecr-docker-push---push-a-docker-container-to-an-aws-ecr-registry)
 * [aws-ecs-utils.sh - Wrapper for simpler operations on AWS ECS](#aws-ecs-utilssh---wrapper-for-simpler-operations-on-aws-ecs)
 * [aws-rds-get-ip.sh - Get AWS RDS IP addresses for running instances](#aws-rds-get-ipsh---get-aws-rds-ip-addresses-for-running-instances)
 * [aws-s3-get-buckets.sh - Get AWS S3 bucket names](#aws-s3-get-bucketssh---get-aws-s3-bucket-names)
 * [aws-select-credentials - Use 'dialog' to select cached AWS credentials and export it into your current shell](#aws-select-credentials---use-'dialog'-to-select-cached-aws-credentials-and-export-it-into-your-current-shell)
 * [aws-select-profile - Use 'dialog' to select an AWS profile and export it into your current shell.](#aws-select-profile---use-'dialog'-to-select-an-aws-profile-and-export-it-into-your-current-shell)
 * [bitbucket-list-all-repos.py - Return a CSV file of Bitbucket repositories](#bitbucket-list-all-repospy---return-a-csv-file-of-bitbucket-repositories)
 * [bitbucket-list-all-repos.sh - Return a JSON document of available Bitbucket repositories for a specific \$BITBUCKET_TEAM](#bitbucket-list-all-repossh---return-a-json-document-of-available-bitbucket-repositories-for-a-specific-\$bitbucket_team)
 * [bitbucket-list-repo-commits.py - Return a CSV of Bitbucket repositories](#bitbucket-list-repo-commitspy---return-a-csv-of-bitbucket-repositories)
 * [bitbucket-manage.py - A management CLI tool for Bitbucket repositories](#bitbucket-managepy---a-management-cli-tool-for-bitbucket-repositories)
 * [bluetooth-reset.sh - Linux bluetooth needs a kick in the pants every time I connect my headset :(](#bluetooth-resetsh---linux-bluetooth-needs-a-kick-in-the-pants-every-time-i-connect-my-headset-:()
 * [bluez-set-a2dp.sh - Try to force-enable A2DP mode for Bluetooth devices](#bluez-set-a2dpsh---try-to-force-enable-a2dp-mode-for-bluetooth-devices)
 * [butler-jenkins-export-import.sh - Use Butlet to export and import jobs and credentials for Jenkins servers](#butler-jenkins-export-importsh---use-butlet-to-export-and-import-jobs-and-credentials-for-jenkins-servers)
 * [cgrep - Wrapper for grep with color mode forced-on](#cgrep---wrapper-for-grep-with-color-mode-forced-on)
 * [circleci-manage.py - A management CLI for CircleCI operations the official CLI doesn't support](#circleci-managepy---a-management-cli-for-circleci-operations-the-official-cli-doesn't-support)
 * [cpufreq-set-all - Set CPU frequency](#cpufreq-set-all---set-cpu-frequency)
 * [csv_row_template_output.py - Generate a set of files based on a Python template and CSV file](#csv_row_template_outputpy---generate-a-set-of-files-based-on-a-python-template-and-csv-file)
 * [d-aws - Run AWS CLI from Docker](#d-aws---run-aws-cli-from-docker)
 * [d-java - Run Java from Docker](#d-java---run-java-from-docker)
 * [d-nr-cli - Run the NewRelic CLI from Docker](#d-nr-cli---run-the-newrelic-cli-from-docker)
 * [d-terraform - Run Terraform CLI from Docker](#d-terraform---run-terraform-cli-from-docker)
 * [date-seconds-portable.sh - A portable implementation of 'date' output, given SECONDS](#date-seconds-portablesh---a-portable-implementation-of-'date'-output-given-seconds)
 * [docker-detach-sshd.sh - Run a detached Docker container with an entrypoint to run an sshd daemon](#docker-detach-sshdsh---run-a-detached-docker-container-with-an-entrypoint-to-run-an-sshd-daemon)
 * [docker-login-list-registries - List Docker CLI config's registries](#docker-login-list-registries---list-docker-cli-config's-registries)
 * [docker-registry-list-repositories - List Docker CLI config's repositories](#docker-registry-list-repositories---list-docker-cli-config's-repositories)
 * [docker-run-1password - Run 1Password CLI using Docker](#docker-run-1password---run-1password-cli-using-docker)
 * [docker-run-gcloud - Run GCloud CLI from Docker](#docker-run-gcloud---run-gcloud-cli-from-docker)
 * [docker-run-op - Run 1Password's 'op' CLI tool with Docker](#docker-run-op---run-1password's-'op'-cli-tool-with-docker)
 * [docker-sshd-entrypoint.sh - Install and run sshd in a Docker container](#docker-sshd-entrypointsh---install-and-run-sshd-in-a-docker-container)
 * [download-aws-secret-env.sh v0.2 - Download AWS Secrets Manager secrets, store in a file, and execute a program](#download-aws-secret-envsh-v02---download-aws-secrets-manager-secrets-store-in-a-file-and-execute-a-program)
 * [download-tls-cert.sh - Download TLS certificate from a host/port](#download-tls-certsh---download-tls-certificate-from-a-host/port)
 * [envsubst.sh - POSIX-compatible version of envsubst](#envsubstsh---posix-compatible-version-of-envsubst)
 * [flatpak-run-slack - Run Slack using Flatpak](#flatpak-run-slack---run-slack-using-flatpak)
 * [flatpak-run-thunderbird - Run Thunderbird using Flatpak](#flatpak-run-thunderbird---run-thunderbird-using-flatpak)
 * [flatpak-run-zoom - Run Zoom using Flatpak](#flatpak-run-zoom---run-zoom-using-flatpak)
 * [gcp-list-service-account-keys.sh - List GCP service account keys](#gcp-list-service-account-keyssh---list-gcp-service-account-keys)
 * [git-askpass-netrc.sh - Use .netrc with Git Askpass](#git-askpass-netrcsh---use-netrc-with-git-askpass)
 * [git-clean-workdir.sh - Clean up temporary files in a Git working directory](#git-clean-workdirsh---clean-up-temporary-files-in-a-git-working-directory)
 * [git-clean.sh - Interactively remove unchecked-in Git working directory files](#git-cleansh---interactively-remove-unchecked-in-git-working-directory-files)
 * [git-cleanup-local-stale.sh - Remove any stale local and remote Git branches from local repository](#git-cleanup-local-stalesh---remove-any-stale-local-and-remote-git-branches-from-local-repository)
 * [git-commit-file.sh - automation for committing files to git](#git-commit-filesh---automation-for-committing-files-to-git)
 * [git-find-ignored.sh - Show all the files in the current Git repo that are being ignored by .gitignore](#git-find-ignoredsh---show-all-the-files-in-the-current-git-repo-that-are-being-ignored-by-gitignore)
 * [git-fix-commit-author.sh - Rewrite Git history to correct the wrong commit author details](#git-fix-commit-authorsh---rewrite-git-history-to-correct-the-wrong-commit-author-details)
 * [git-grep-entire-repo-history.sh - Grep the entire history of a Git repository](#git-grep-entire-repo-historysh---grep-the-entire-history-of-a-git-repository)
 * [git-http-check-origin-exists.sh - In case you want to use 'curl' to see if an HTTP(s) Git repo actually exists or not](#git-http-check-origin-existssh---in-case-you-want-to-use-'curl'-to-see-if-an-http(s)-git-repo-actually-exists-or-not)
 * [git-lfs-compare.sh - Compare the files in a Git repository with the files in Git LFS](#git-lfs-comparesh---compare-the-files-in-a-git-repository-with-the-files-in-git-lfs)
 * [git-list-branch-by-date.sh - List Git branches by date of last commit](#git-list-branch-by-datesh---list-git-branches-by-date-of-last-commit)
 * [git-list-repo-files.sh - List all files checked into a git repository](#git-list-repo-filessh---list-all-files-checked-into-a-git-repository)
 * [git-list-untracked-ignored.sh - List untracked and ignored files in a Git repository](#git-list-untracked-ignoredsh---list-untracked-and-ignored-files-in-a-git-repository)
 * [git-list-untracked.sh - List untracked files in a Git repository](#git-list-untrackedsh---list-untracked-files-in-a-git-repository)
 * [git-permanently-remove-file-from-repo.sh - Rewrite history to permanently remove a file from a Git repository](#git-permanently-remove-file-from-reposh---rewrite-history-to-permanently-remove-a-file-from-a-git-repository)
 * [git-push-force-all.sh - Force-push a Git repository (with tags)](#git-push-force-allsh---force-push-a-git-repository-(with-tags))
 * [git-show-commit-authors.sh - List all of the commit authors in a Git repository](#git-show-commit-authorssh---list-all-of-the-commit-authors-in-a-git-repository)
 * [git-show-mainline-branch.sh - Attempt to show mainline branch of a Git repository](#git-show-mainline-branchsh---attempt-to-show-mainline-branch-of-a-git-repository)
 * [git-squash-current-branch.sh - Squash your current branch's commits, based on MAINBRANCH](#git-squash-current-branchsh---squash-your-current-branch's-commits-based-on-mainbranch)
 * [github-get-pr - Get a pull request branch from GitHub](#github-get-pr---get-a-pull-request-branch-from-github)
 * [github-get-restapi.sh - Curl the GitHub API](#github-get-restapish---curl-the-github-api)
 * [github-get-team-members.sh - Use get-github-restapi.sh to get GitHub team members list](#github-get-team-memberssh---use-get-github-restapish-to-get-github-team-members-list)
 * [github-get-team.sh - Use get-github-restapi.sh to get GitHub teams list](#github-get-teamsh---use-get-github-restapish-to-get-github-teams-list)
 * [github-list-users.py - List GitHub users using 'github' Python library](#github-list-userspy---list-github-users-using-'github'-python-library)
 * [github-set-commit-build-status.sh - Set commit build status for a GitHub commit](#github-set-commit-build-statussh---set-commit-build-status-for-a-github-commit)
 * [gw - A Terminal User Interface wrapper to make Git worktrees easier to manage](#gw---a-terminal-user-interface-wrapper-to-make-git-worktrees-easier-to-manage)
 * [helm-list-fast.sh - a much faster version of 'helm list -A'](#helm-list-fastsh---a-much-faster-version-of-'helm-list--a')
 * [jenkins-add-credential.sh - Adds a credential to Jenkins credential store via REST API](#jenkins-add-credentialsh---adds-a-credential-to-jenkins-credential-store-via-rest-api)
 * [jenkins-curl-wrapper.sh - Loads Jenkins authentication information and runs curl, passing in command-line arguments.](#jenkins-curl-wrappersh---loads-jenkins-authentication-information-and-runs-curl-passing-in-command-line-arguments)
 * [jenkins-generate-user-token.sh - Generates a Jenkins user token](#jenkins-generate-user-tokensh---generates-a-jenkins-user-token)
 * [jenkins-groovy-remote.sh - Run a Groovy file on a Jenkins server (via the API)](#jenkins-groovy-remotesh---run-a-groovy-file-on-a-jenkins-server-(via-the-api))
 * [jenkins-run-groovy-remote.sh - Takes a groovy file, replaces some variables, and executes it on a remote Jenkins instance.](#jenkins-run-groovy-remotesh---takes-a-groovy-file-replaces-some-variables-and-executes-it-on-a-remote-jenkins-instance)
 * [jenkins-run-job-with-parameter-defaults.py - Run a Jenkins job with parameters](#jenkins-run-job-with-parameter-defaultspy---run-a-jenkins-job-with-parameters)
 * [jenkins-trigger-paramaterized-build.py - Run a Jenkins parameterized build](#jenkins-trigger-paramaterized-buildpy---run-a-jenkins-parameterized-build)
 * [jenkinsctl - a command-line wrapper around building and running a Jenkins instance](#jenkinsctl---a-command-line-wrapper-around-building-and-running-a-jenkins-instance)
 * [k8s-copy-secret-across-namespace.sh - Copy a Kubernetes secret into a new namespace](#k8s-copy-secret-across-namespacesh---copy-a-kubernetes-secret-into-a-new-namespace)
 * [k8s-curl.sh - Curl the K8s API, from within a K8s pod](#k8s-curlsh---curl-the-k8s-api-from-within-a-k8s-pod)
 * [k8s-deployment-restart.sh - Restart a K8s deployment](#k8s-deployment-restartsh---restart-a-k8s-deployment)
 * [k8s-diagnose-site.sh - Attempt to diagnose a web site in K8s](#k8s-diagnose-sitesh---attempt-to-diagnose-a-web-site-in-k8s)
 * [k8s-diff-secret-by-ns.sh - Diff k8s secrets between two namespaces](#k8s-diff-secret-by-nssh---diff-k8s-secrets-between-two-namespaces)
 * [k8s-diff-secret.sh - Diff k8s secrets (this is broken)](#k8s-diff-secretsh---diff-k8s-secrets-(this-is-broken))
 * [k8s-find-all-resources.sh - Find all Kubernetes resources](#k8s-find-all-resourcessh---find-all-kubernetes-resources)
 * [k8s-get-events-notnormal.sh - Get all Kubernetes events not of type 'Normal'](#k8s-get-events-notnormalsh---get-all-kubernetes-events-not-of-type-'normal')
 * [k8s-get-pod-logs.sh - Save any Crashing, Error, or Failed pods' logs to a file](#k8s-get-pod-logssh---save-any-crashing-error-or-failed-pods'-logs-to-a-file)
 * [k8s-get-pods-running.sh - Get running K8s pods](#k8s-get-pods-runningsh---get-running-k8s-pods)
 * [k8s-get-secret-values.sh - Output kubernetes secret keys and values in plaintext](#k8s-get-secret-valuessh---output-kubernetes-secret-keys-and-values-in-plaintext)
 * [k8s-get-secrets-opaque.sh - Get any 'Opaque' type k8s secrets](#k8s-get-secrets-opaquesh---get-any-'opaque'-type-k8s-secrets)
 * [k8s-run-shell.sh - Start a K8s pod and open an interactive shell, then destroy it on exit](#k8s-run-shellsh---start-a-k8s-pod-and-open-an-interactive-shell-then-destroy-it-on-exit)
 * [k8s-show-error.sh - Show K8s errors for Certificate Manager](#k8s-show-errorsh---show-k8s-errors-for-certificate-manager)
 * [kd - A Terminal User Interface wrapper for Kubernetes commands](#kd---a-terminal-user-interface-wrapper-for-kubernetes-commands)
 * [load-vim-plugins.sh - Load VIM plugins](#load-vim-pluginssh---load-vim-plugins)
 * [make-readme.sh - Generates a README.md based on the comment descriptions after a shebang in a script](#make-readmesh---generates-a-readmemd-based-on-the-comment-descriptions-after-a-shebang-in-a-script)
 * [move-files-to-folders-by-ext.sh - Move all the files in a directory into folders named by extension](#move-files-to-folders-by-extsh---move-all-the-files-in-a-directory-into-folders-named-by-extension)
 * [NOTE: I don't know who wrote this?? It was probably downloaded from the internet?](#note:-i-don't-know-who-wrote-this??-it-was-probably-downloaded-from-the-internet?)
 * [notes.sh - shell script to manage hierarchy of note files](#notessh---shell-script-to-manage-hierarchy-of-note-files)
 * [python-stdin-to-json.py - Dump standard input stream as a JSON-formatted output](#python-stdin-to-jsonpy---dump-standard-input-stream-as-a-json-formatted-output)
 * [random-dict-password.sh - Generate a random password from dictionary words](#random-dict-passwordsh---generate-a-random-password-from-dictionary-words)
 * [random-password.sh - Generate a random password](#random-passwordsh---generate-a-random-password)
 * [remote-gpg - Run gpg operations on a remote host](#remote-gpg---run-gpg-operations-on-a-remote-host)
 * [reset-ntp.sh - Update the time on a box using ntp](#reset-ntpsh---update-the-time-on-a-box-using-ntp)
 * [ssh - ssh wrapper to override TERM setting so that ssh will send the one we want remotely](#ssh---ssh-wrapper-to-override-term-setting-so-that-ssh-will-send-the-one-we-want-remotely)
 * [ssh-config-hosts.sh - Recursively find any 'Host <host>' lines in local ssh configs](#ssh-config-hostssh---recursively-find-any-'host-<host>'-lines-in-local-ssh-configs)
 * [ssh-mass-run-script.sh - send a script to a lot of hosts and then execute it on them](#ssh-mass-run-scriptsh---send-a-script-to-a-lot-of-hosts-and-then-execute-it-on-them)
 * [terraform-find-missing-vars.pl - Find missing variable definitions in a Terraform module](#terraform-find-missing-varspl---find-missing-variable-definitions-in-a-terraform-module)
 * [ubuntu-18.04-setup-dnsmasq.sh - Set up DNSMASQ on Ubuntu 18.04](#ubuntu-1804-setup-dnsmasqsh---set-up-dnsmasq-on-ubuntu-1804)
 * [ubuntu-list-pkgs-by-date.sh - Self explanatory](#ubuntu-list-pkgs-by-datesh---self-explanatory)
 * [uniqunsort - Remove duplicated lines from stdin, print to stdout](#uniqunsort---remove-duplicated-lines-from-stdin-print-to-stdout)
 * [urlencode.sh - Print a string URL-encoded](#urlencodesh---print-a-string-url-encoded)
 * [virtualenv - Run virtualenv, installing it if needed](#virtualenv---run-virtualenv-installing-it-if-needed)
 * [wget-mirror.sh - Use Wget to create a mirror of a website](#wget-mirrorsh---use-wget-to-create-a-mirror-of-a-website)
 * [wordpress-salt-envs.sh - Download the default salts for WordPress](#wordpress-salt-envssh---download-the-default-salts-for-wordpress)
 * [xml-lint - Wrapper around xmlllint to install it if necessary](#xml-lint---wrapper-around-xmlllint-to-install-it-if-necessary)
---


## [ad-ldap-tool.sh - Search Microsoft Active Directory using ldapsearch](./ad-ldap-tool.sh)
<blockquote>
</blockquote>


## [apt-update-security-packages.sh - Update Apt packages for security updates](./apt-update-security-packages.sh)
<blockquote>
</blockquote>


## [aws-adfs-profile-login - Login to AWS with aws-adfs, using AWS profiles](./aws-adfs-profile-login)
<blockquote>
</blockquote>


## [aws-assume-admin-role - Assume an admin role and execute arbitrary commands](./aws-assume-admin-role)
<blockquote>
</blockquote>


## [aws-assume-role - A wrapper to make it easier to assume AWS roles](./aws-assume-role)
<blockquote>

The following is specifically written to return an exit code,
_without exiting the current shell session_.
This way this will work when sourced into a script, without
exiting the parent script.
</blockquote>


## [aws-cli-cache-auth-keys.sh - Extract the auth keys from a cached AWS CLI authentication json file](./aws-cli-cache-auth-keys.sh)
<blockquote>
</blockquote>


## [aws-create-update-secret - Create or update an AWS Secrets Manager secret](./aws-create-update-secret)
<blockquote>

This script is only used the first time we create a secret.
It's part of a bootstrap process, or when a new application is added.
</blockquote>


## [aws-ec2-describe-sec-group-rules.sh - Print a TSV of AWS EC2 security group rules](./aws-ec2-describe-sec-group-rules.sh)
<blockquote>
</blockquote>


## [aws-ec2-get-instance-id.sh - Get the Instance ID of running AWS EC2 instances](./aws-ec2-get-instance-id.sh)
<blockquote>
</blockquote>


## [aws-ec2-get-ip.sh - Get the IPs of running AWS EC2 instances](./aws-ec2-get-ip.sh)
<blockquote>
</blockquote>


## [aws-ec2-get-network-interface-public-ips.sh - Get the public IP of AWS EC2 network interfaces](./aws-ec2-get-network-interface-public-ips.sh)
<blockquote>
</blockquote>


## [aws-ec2-get-running-instances.sh - Get the Instance ID, key name, group ID, and public IP of running AWS EC2 instances](./aws-ec2-get-running-instances.sh)
<blockquote>
</blockquote>


## [aws-ec2-get-security-groups.sh - Get AWS EC2 security groups](./aws-ec2-get-security-groups.sh)
<blockquote>
</blockquote>


## [aws-ec2-get-sg-ids.sh - Get AWS EC2 instance security group IDs](./aws-ec2-get-sg-ids.sh)
<blockquote>
</blockquote>


## [aws-ecr-create-repository - Create an AWS ECR repository](./aws-ecr-create-repository)
<blockquote>
</blockquote>


## [aws-ecr-docker-login - Perform a Docker login to an AWS ECR repository](./aws-ecr-docker-login)
<blockquote>
</blockquote>


## [aws-ecr-docker-pull - Pull a Docker image from an AWS ECR registry](./aws-ecr-docker-pull)
<blockquote>
</blockquote>


## [aws-ecr-docker-push - Push a Docker container to an AWS ECR registry](./aws-ecr-docker-push)
<blockquote>
</blockquote>


## [aws-ecs-utils.sh - Wrapper for simpler operations on AWS ECS](./aws-ecs-utils.sh)
<blockquote>
</blockquote>


## [aws-rds-get-ip.sh - Get AWS RDS IP addresses for running instances](./aws-rds-get-ip.sh)
<blockquote>
</blockquote>


## [aws-s3-get-buckets.sh - Get AWS S3 bucket names](./aws-s3-get-buckets.sh)
<blockquote>
</blockquote>


## [aws-select-credentials - Use 'dialog' to select cached AWS credentials and export it into your current shell](./aws-select-credentials)
<blockquote>

Assuming this script is in your PATH, simply run:
  $ `aws-select-credentials`
or:
  $ . aws-select-credentials
</blockquote>


## [aws-select-profile - Use 'dialog' to select an AWS profile and export it into your current shell.](./aws-select-profile)
<blockquote>

Assuming this script is in your PATH, simply run:
  $ `aws-select-profile`
or:
  $ . aws-select-profile
</blockquote>


## [bitbucket-list-all-repos.py - Return a CSV file of Bitbucket repositories](./bitbucket-list-all-repos.py)
<blockquote>
</blockquote>


## [bitbucket-list-all-repos.sh - Return a JSON document of available Bitbucket repositories for a specific \$BITBUCKET_TEAM](./bitbucket-list-all-repos.sh)
<blockquote>
</blockquote>


## [bitbucket-list-repo-commits.py - Return a CSV of Bitbucket repositories](./bitbucket-list-repo-commits.py)
<blockquote>
</blockquote>


## [bitbucket-manage.py - A management CLI tool for Bitbucket repositories](./bitbucket-manage.py)
<blockquote>
</blockquote>


## [bluetooth-reset.sh - Linux bluetooth needs a kick in the pants every time I connect my headset :(](./bluetooth-reset.sh)
<blockquote>
</blockquote>


## [bluez-set-a2dp.sh - Try to force-enable A2DP mode for Bluetooth devices](./bluez-set-a2dp.sh)
<blockquote>
</blockquote>


## [butler-jenkins-export-import.sh - Use Butlet to export and import jobs and credentials for Jenkins servers](./butler-jenkins-export-import.sh)
<blockquote>
</blockquote>


## [cgrep - Wrapper for grep with color mode forced-on](./cgrep)
<blockquote>
</blockquote>


## [circleci-manage.py - A management CLI for CircleCI operations the official CLI doesn't support](./circleci-manage.py)
<blockquote>
</blockquote>


## [cpufreq-set-all - Set CPU frequency](./cpufreq-set-all)
<blockquote>
</blockquote>


## [csv_row_template_output.py - Generate a set of files based on a Python template and CSV file](./csv_row_template_output.py)
<blockquote>
</blockquote>


## [d-aws - Run AWS CLI from Docker](./d-aws)
<blockquote>
</blockquote>


## [d-java - Run Java from Docker](./d-java)
<blockquote>
</blockquote>


## [d-nr-cli - Run the NewRelic CLI from Docker](./d-nr-cli)
<blockquote>
</blockquote>


## [d-terraform - Run Terraform CLI from Docker](./d-terraform)
<blockquote>
</blockquote>


## [date-seconds-portable.sh - A portable implementation of 'date' output, given SECONDS](./date-seconds-portable.sh)
<blockquote>
</blockquote>


## [NOTE: I don't know who wrote this?? It was probably downloaded from the internet?](./docker-delete-registry-image.py)
<blockquote>
- Peter
</blockquote>


## [docker-detach-sshd.sh - Run a detached Docker container with an entrypoint to run an sshd daemon](./docker-detach-sshd.sh)
<blockquote>

Before running this script, create an ssh key on the local host:
      ssh-keygen -t ed25519 -N ''

Set PUBKEY to the public key file created.
Then run the sshd container below.

This will volume-map the host's docker.sock,
make a persistent Terraform plugin cache,
a persistent volume for miscellaneous uses,
the SSH public key created above (so we can login with it),
maps in the entrypoint to set up and start sshd,
and exports the sshd port to the local host.
</blockquote>


## [docker-login-list-registries - List Docker CLI config's registries](./docker-login-list-registries)
<blockquote>
</blockquote>


## [docker-registry-list-repositories - List Docker CLI config's repositories](./docker-registry-list-repositories)
<blockquote>
</blockquote>


## [docker-run-1password - Run 1Password CLI using Docker](./docker-run-1password)
<blockquote>
</blockquote>


## [docker-run-gcloud - Run GCloud CLI from Docker](./docker-run-gcloud)
<blockquote>
</blockquote>


## [docker-run-op - Run 1Password's 'op' CLI tool with Docker](./docker-run-op)
<blockquote>
</blockquote>


## [docker-sshd-entrypoint.sh - Install and run sshd in a Docker container](./docker-sshd-entrypoint.sh)
<blockquote>
</blockquote>


## [download-aws-secret-env.sh v0.2 - Download AWS Secrets Manager secrets, store in a file, and execute a program](./download-aws-secret-env.sh)
<blockquote>
</blockquote>


## [download-tls-cert.sh - Download TLS certificate from a host/port](./download-tls-cert.sh)
<blockquote>
</blockquote>


## [envsubst.sh - POSIX-compatible version of envsubst](./envsubst.sh)
<blockquote>

Feed it text on standard input, and it prints the text to standard output,
replacing ${FOO} or $FOO in the text with the value of the variable.

This is *very* slow, but it's about as fast as I can get it using just
POSIX shell stuff (sed/awk would be faster). Use GNU envsubst for speed.

Since this is a shell script, it conflates shell variables with
environment variables. You can load this script into your shell
and it will use those variables specific to your shell session:
    cat Sample.txt | . ./envsubst.sh

Or you can call this script as an external executable and it will
use only exported variables:
    cat Sample.txt | ./envsubst.sh

</blockquote>


## [flatpak-run-slack - Run Slack using Flatpak](./flatpak-run-slack)
<blockquote>
</blockquote>


## [flatpak-run-thunderbird - Run Thunderbird using Flatpak](./flatpak-run-thunderbird)
<blockquote>
</blockquote>


## [flatpak-run-zoom - Run Zoom using Flatpak](./flatpak-run-zoom)
<blockquote>
</blockquote>


## [gcp-list-service-account-keys.sh - List GCP service account keys](./gcp-list-service-account-keys.sh)
<blockquote>
</blockquote>


## [git-askpass-netrc.sh - Use .netrc with Git Askpass](./git-askpass-netrc.sh)
<blockquote>

This is mostly unnecessary right now. It was written with the idea that maybe
one could use a fake username and then substitute it later with a new username
and a specific personal access token.

I think the solution is to turn this into a 'credential helper' which can
take different arguments and actually return both a username and password.
</blockquote>


## [git-clean-workdir.sh - Clean up temporary files in a Git working directory](./git-clean-workdir.sh)
<blockquote>
</blockquote>


## [git-clean.sh - Interactively remove unchecked-in Git working directory files](./git-clean.sh)
<blockquote>
</blockquote>


## [git-cleanup-local-stale.sh - Remove any stale local and remote Git branches from local repository](./git-cleanup-local-stale.sh)
<blockquote>
</blockquote>


## [git-commit-file.sh - automation for committing files to git](./git-commit-file.sh)
<blockquote>
</blockquote>


## [git-find-ignored.sh - Show all the files in the current Git repo that are being ignored by .gitignore](./git-find-ignored.sh)
<blockquote>
</blockquote>


## [git-fix-commit-author.sh - Rewrite Git history to correct the wrong commit author details](./git-fix-commit-author.sh)
<blockquote>
</blockquote>


## [git-grep-entire-repo-history.sh - Grep the entire history of a Git repository](./git-grep-entire-repo-history.sh)
<blockquote>
</blockquote>


## [git-http-check-origin-exists.sh - In case you want to use 'curl' to see if an HTTP(s) Git repo actually exists or not](./git-http-check-origin-exists.sh)
<blockquote>
</blockquote>


## [git-lfs-compare.sh - Compare the files in a Git repository with the files in Git LFS](./git-lfs-compare.sh)
<blockquote>
</blockquote>


## [git-list-branch-by-date.sh - List Git branches by date of last commit](./git-list-branch-by-date.sh)
<blockquote>
</blockquote>


## [git-list-repo-files.sh - List all files checked into a git repository](./git-list-repo-files.sh)
<blockquote>
</blockquote>


## [git-list-untracked-ignored.sh - List untracked and ignored files in a Git repository](./git-list-untracked-ignored.sh)
<blockquote>
</blockquote>


## [git-list-untracked.sh - List untracked files in a Git repository](./git-list-untracked.sh)
<blockquote>
</blockquote>


## [git-permanently-remove-file-from-repo.sh - Rewrite history to permanently remove a file from a Git repository](./git-permanently-remove-file-from-repo.sh)
<blockquote>
</blockquote>


## [git-push-force-all.sh - Force-push a Git repository (with tags)](./git-push-force-all.sh)
<blockquote>
</blockquote>


## [git-show-commit-authors.sh - List all of the commit authors in a Git repository](./git-show-commit-authors.sh)
<blockquote>
</blockquote>


## [git-show-mainline-branch.sh - Attempt to show mainline branch of a Git repository](./git-show-mainline-branch.sh)
<blockquote>
</blockquote>


## [git-squash-current-branch.sh - Squash your current branch's commits, based on MAINBRANCH](./git-squash-current-branch.sh)
<blockquote>

From https://stackoverflow.com/a/25357146/3760330
</blockquote>


## [github-get-pr - Get a pull request branch from GitHub](./github-get-pr)
<blockquote>
</blockquote>


## [github-get-restapi.sh - Curl the GitHub API](./github-get-restapi.sh)
<blockquote>
</blockquote>


## [github-get-team-members.sh - Use get-github-restapi.sh to get GitHub team members list](./github-get-team-members.sh)
<blockquote>
</blockquote>


## [github-get-team.sh - Use get-github-restapi.sh to get GitHub teams list](./github-get-team.sh)
<blockquote>
</blockquote>


## [github-list-users.py - List GitHub users using 'github' Python library](./github-list-users.py)
<blockquote>
</blockquote>


## [github-set-commit-build-status.sh - Set commit build status for a GitHub commit](./github-set-commit-build-status.sh)
<blockquote>
</blockquote>


## [gw - A Terminal User Interface wrapper to make Git worktrees easier to manage](./gw)
<blockquote>
</blockquote>


## [helm-list-fast.sh - a much faster version of 'helm list -A'](./helm-list-fast.sh)
<blockquote>

About:
  This script exists because 'helm list' will query the Kubernetes API server
  in such a way that secrets take a looooong time to come back.
  To avoid that wait, here I just grab the secrets list with kubectl, and then
  parallelize grabbing individual last release files to determine their last
  updated date.
  This is about 6x faster than 'helm list' (on my cluster).

Requires:
  - kubectl, base64, gzip, jq, xargs, column

TODO:
 - add columns 'STATUS', 'CHART', 'APP VERSION'
 - support single-namespace operation
</blockquote>


## [jenkins-add-credential.sh - Adds a credential to Jenkins credential store via REST API](./jenkins-add-credential.sh)
<blockquote>

Example:

  $ JENKINS_SERVER_URL=https://foo.com/ \
      ./add-jenkins-credential.sh easi-github-token <redacted>
</blockquote>


## [jenkins-curl-wrapper.sh - Loads Jenkins authentication information and runs curl, passing in command-line arguments.](./jenkins-curl-wrapper.sh)
<blockquote>

Re-use this to call curl on Jenkins servers.
By default gets and inserts a CSRF crumb in header.
Pass in '-XGET' or '-XPOST' followed by the rest of your arguments, depending
on the API calls you're making.

et -Eeuo pipefail
</blockquote>


## [jenkins-generate-user-token.sh - Generates a Jenkins user token](./jenkins-generate-user-token.sh)
<blockquote>
</blockquote>


## [jenkins-groovy-remote.sh - Run a Groovy file on a Jenkins server (via the API)](./jenkins-groovy-remote.sh)
<blockquote>
</blockquote>


## [jenkins-run-groovy-remote.sh - Takes a groovy file, replaces some variables, and executes it on a remote Jenkins instance.](./jenkins-run-groovy-remote.sh)
<blockquote>

Sample groovy file:
  print "ls -la".execute().getText()
</blockquote>


## [jenkins-run-job-with-parameter-defaults.py - Run a Jenkins job with parameters](./jenkins-run-job-with-parameter-defaults.py)
<blockquote>
</blockquote>


## [jenkins-trigger-paramaterized-build.py - Run a Jenkins parameterized build](./jenkins-trigger-paramaterized-build.py)
<blockquote>
</blockquote>


## [jenkinsctl - a command-line wrapper around building and running a Jenkins instance](./jenkinsctl)
<blockquote>
</blockquote>


## [k8s-copy-secret-across-namespace.sh - Copy a Kubernetes secret into a new namespace](./k8s-copy-secret-across-namespace.sh)
<blockquote>
</blockquote>


## [k8s-curl.sh - Curl the K8s API, from within a K8s pod](./k8s-curl.sh)
<blockquote>
</blockquote>


## [k8s-deployment-restart.sh - Restart a K8s deployment](./k8s-deployment-restart.sh)
<blockquote>
</blockquote>


## [k8s-diagnose-site.sh - Attempt to diagnose a web site in K8s](./k8s-diagnose-site.sh)
<blockquote>
</blockquote>


## [k8s-diff-secret-by-ns.sh - Diff k8s secrets between two namespaces](./k8s-diff-secret-by-ns.sh)
<blockquote>
</blockquote>


## [k8s-diff-secret.sh - Diff k8s secrets (this is broken)](./k8s-diff-secret.sh)
<blockquote>
</blockquote>


## [k8s-find-all-resources.sh - Find all Kubernetes resources](./k8s-find-all-resources.sh)
<blockquote>
</blockquote>


## [k8s-get-events-notnormal.sh - Get all Kubernetes events not of type 'Normal'](./k8s-get-events-notnormal.sh)
<blockquote>
</blockquote>


## [k8s-get-pod-logs.sh - Save any Crashing, Error, or Failed pods' logs to a file](./k8s-get-pod-logs.sh)
<blockquote>
</blockquote>


## [k8s-get-pods-running.sh - Get running K8s pods](./k8s-get-pods-running.sh)
<blockquote>
</blockquote>


## [k8s-get-secret-values.sh - Output kubernetes secret keys and values in plaintext](./k8s-get-secret-values.sh)
<blockquote>
</blockquote>


## [k8s-get-secrets-opaque.sh - Get any 'Opaque' type k8s secrets](./k8s-get-secrets-opaque.sh)
<blockquote>
</blockquote>


## [k8s-run-shell.sh - Start a K8s pod and open an interactive shell, then destroy it on exit](./k8s-run-shell.sh)
<blockquote>

Installs some basic packages and drop user into command prompt in a screen session.
On exit, pod is deleted.

All arguments are passed to 'kubectl run' before the command arguments,
so you can pass things like the k8s namespace.
</blockquote>


## [k8s-show-error.sh - Show K8s errors for Certificate Manager](./k8s-show-error.sh)
<blockquote>
</blockquote>


## [kd - A Terminal User Interface wrapper for Kubernetes commands](./kd)
<blockquote>

kd is a wrapper around common kubernetes commands to simplify running various
k8s tasks without needing to remember commands or rely on bash-completion.
It supplies a text UI (optionally using the 'dialog' tool) for prompts.

Run 'kd' and select a command, or select DEFAULT to always use the defaults.
</blockquote>


## [load-vim-plugins.sh - Load VIM plugins](./load-vim-plugins.sh)
<blockquote>
</blockquote>


## [make-readme.sh - Generates a README.md based on the comment descriptions after a shebang in a script](./make-readme.sh)
<blockquote>
</blockquote>


## [move-files-to-folders-by-ext.sh - Move all the files in a directory into folders named by extension](./move-files-to-folders-by-ext.sh)
<blockquote>
</blockquote>


## [notes.sh - shell script to manage hierarchy of note files](./notes.sh)
<blockquote>
</blockquote>


## [python-stdin-to-json.py - Dump standard input stream as a JSON-formatted output](./python-stdin-to-json.py)
<blockquote>
</blockquote>


## [random-dict-password.sh - Generate a random password from dictionary words](./random-dict-password.sh)
<blockquote>
</blockquote>


## [random-password.sh - Generate a random password](./random-password.sh)
<blockquote>
</blockquote>


## [remote-gpg - Run gpg operations on a remote host](./remote-gpg)
<blockquote>

original author: Dustin J. Mitchell <dustin@cs.uchicago.edu>
</blockquote>


## [reset-ntp.sh - Update the time on a box using ntp](./reset-ntp.sh)
<blockquote>
</blockquote>


## [ssh - ssh wrapper to override TERM setting so that ssh will send the one we want remotely](./ssh)
<blockquote>
</blockquote>


## [ssh-config-hosts.sh - Recursively find any 'Host <host>' lines in local ssh configs](./ssh-config-hosts.sh)
<blockquote>

Usage: ssh-config-hosts [FILE]
</blockquote>


## [ssh-mass-run-script.sh - send a script to a lot of hosts and then execute it on them](./ssh-mass-run-script.sh)
<blockquote>

Note: this script does not fail on error, in order to work on as many hosts as possible.
</blockquote>


## [terraform-find-missing-vars.pl - Find missing variable definitions in a Terraform module](./terraform-find-missing-vars.pl)
<blockquote>
</blockquote>


## [ubuntu-18.04-setup-dnsmasq.sh - Set up DNSMASQ on Ubuntu 18.04](./ubuntu-18.04-setup-dnsmasq.sh)
<blockquote>
</blockquote>


## [ubuntu-list-pkgs-by-date.sh - Self explanatory](./ubuntu-list-pkgs-by-date.sh)
<blockquote>
</blockquote>


## [uniqunsort - Remove duplicated lines from stdin, print to stdout](./uniqunsort)
<blockquote>
</blockquote>


## [urlencode.sh - Print a string URL-encoded](./urlencode.sh)
<blockquote>
</blockquote>


## [virtualenv - Run virtualenv, installing it if needed](./virtualenv)
<blockquote>
</blockquote>


## [wget-mirror.sh - Use Wget to create a mirror of a website](./wget-mirror.sh)
<blockquote>
</blockquote>


## [wordpress-salt-envs.sh - Download the default salts for WordPress](./wordpress-salt-envs.sh)
<blockquote>
</blockquote>


## [xml-lint - Wrapper around xmlllint to install it if necessary](./xml-lint)
<blockquote>
</blockquote>


