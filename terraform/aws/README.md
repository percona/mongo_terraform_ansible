# Deploy MongoDB infrastructure on AWS

Percona ClusterSync is disabled by default. Set `enable_pcsm=true` to create one dedicated `t3.small` VM in the environment VPC. Only SSH is allowed inbound; API port `2242` is not exposed. Generated inventories and SSH configuration expose `${prefix}-pcsm`. Supply an already-generated secure environment file to Ansible through `pcsm_env_file_source`; Terraform never receives its contents. The package version defaults to `pcsm_version="0.9.0"`.

## Percona ClusterSync

Set `pcsm_source_kind` and `pcsm_target_kind` to `cluster` or `replset`, and set the matching names from `clusters` or `replsets`. Both kinds must match and the names must differ. `cluster` selects its mongos hosts; `replset` selects its data-bearing electable members. With PCSM enabled, `terraform apply` writes `<prefix>_inventory_pcsm`, which includes every topology using the normal inventory group names plus `[pcsm]`, `[pcsm_source]`, and `[pcsm_target]`.

```bash
terraform apply
ansible-playbook -i <prefix>_inventory_pcsm ../../ansible/main.yml
ansible-playbook -i <prefix>_inventory_pcsm ../../ansible/main.yml --tags pcsm -e pcsm_env_file_source=/secure/path/pcsm.env
```

This Terraform module creates:

- a VPC, public subnets, an internet gateway, routes, and security groups
- a private Route 53 zone and records
- EC2 instances and EBS volumes for MongoDB and optional supporting services
- an EC2 key pair
- an S3 backup bucket with lifecycle and versioning configuration
- a PBM IAM user, access key, role, and S3 access policies
- generated Ansible inventory and SSH configuration files

## Prerequisites

- Terraform 1.9 or newer
- Ansible and OpenSSH
- an existing SSH key pair
- an AWS account and an administrator who can create an IAM user, attach policies,
  and create an access key

Install the local tools and AWS CLI from the repository root:

```bash
./scripts/install-prerequisites.sh --aws
```

The AWS CLI is required by the Web UI. Manual Terraform usage can use any
authentication method supported by the AWS provider, including an AWS profile,
environment variables, IAM Identity Center, or an assumed role.

## Create the AWS deployment user

The following setup uses a dedicated IAM user because the Web UI accepts an AWS
access key. Run these commands as an AWS administrator. For manual deployments,
an IAM Identity Center or assumed-role profile with the same permissions is
preferred when available because it avoids a long-lived access key.

1. Create the deployment user:

```bash
export AWS_DEPLOY_USER=mongodb-terraform-deployer
aws iam create-user --user-name "$AWS_DEPLOY_USER"
```

2. Attach the managed policies needed for the resources declared by this module:

```bash
aws iam attach-user-policy --user-name "$AWS_DEPLOY_USER" \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-user-policy --user-name "$AWS_DEPLOY_USER" \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
aws iam attach-user-policy --user-name "$AWS_DEPLOY_USER" \
  --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess
aws iam attach-user-policy --user-name "$AWS_DEPLOY_USER" \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-user-policy --user-name "$AWS_DEPLOY_USER" \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
```

`IAMFullAccess` is required because Terraform creates and destroys a separate IAM
user, access key, role, and inline policies for PBM backup access. These managed
policies are broad. Use a custom least-privilege policy if your organization
requires tighter controls, ensuring that it covers all EC2, EBS, VPC, Route 53,
S3, and IAM resources declared under this directory.

3. Create an access key. The secret is displayed only once, so store it in your
   approved secret manager:

```bash
aws iam create-access-key --user-name "$AWS_DEPLOY_USER"
```

4. Configure and verify a local profile using the returned access key and the
   region configured in `variables.tf`:

```bash
aws configure --profile mongodb-terraform
export AWS_PROFILE=mongodb-terraform
aws sts get-caller-identity
```

For the Web UI, enter the access key, secret access key, region, and profile name
in **Settings**. The UI stores isolated AWS credential files under
`ui-go/secrets/cloud/aws/` and sets `AWS_SHARED_CREDENTIALS_FILE`,
`AWS_CONFIG_FILE`, and `AWS_PROFILE` for Terraform.

## Configure the deployment

Change into the AWS Terraform directory:

```bash
cd terraform/aws
```

Review `variables.tf`, then put overrides in `terraform.tfvars` or another tfvars
file. At minimum, review:

- `prefix`, `region`, `clusters`, and `replsets`
- `ssh_public_key_path`, `ssh_private_key_path`, and `my_ssh_user`
- instance types, AMI, EBS sizes, and `use_spot_instances`
- backup bucket naming and retention
- network rules, noting that `source_ranges` currently applies only to the dedicated CA host
- optional PMM, CA/TLS, LDAP, and YCSB settings

The checked-in `rs.tfvars` is an example standalone replica-set configuration.

## Deploy

Initialize and review the Terraform plan before applying it:

```bash
terraform init
terraform plan
terraform apply
```

When using a non-default variable file, pass the same file to every command:

```bash
terraform plan -var-file=rs.tfvars
terraform apply -var-file=rs.tfvars
```

Terraform creates one inventory and SSH config per topology:

- `<prefix>_inventory_<cluster-or-replset>`
- `<prefix>_ssh_config_<cluster-or-replset>`

Optionally append a generated SSH configuration to your local configuration:

```bash
cat myenv_ssh_config_cl01 >> ~/.ssh/config
```

Run Ansible directly against the generated inventory from this directory:

```bash
ansible-playbook -i myenv_inventory_cl01 ../../ansible/main.yml
```

Typical provisioning takes about 1 minute for the infrastructure and about 15
minutes for Ansible to configure a 2-shard cluster.

## Connecting

If you appended the generated SSH configuration, connect by host alias:

```bash
ssh my-cluster-name-mongodb-cfg01
```

## Backup credentials and sensitive files

Terraform creates a separate PBM IAM user and access key restricted to the
created S3 bucket. These are not the deployment user's credentials. Inspect
outputs when needed with:

```bash
terraform output -json
```

The PBM secret is stored in Terraform state and generated inventory files. Keep
state, tfvars, inventories, SSH configuration, and UI secret directories out of
source control and restrict their filesystem permissions.

## Network security

Instances receive public IP addresses. Most SSH and ICMP security-group rules are
currently hard-coded to `0.0.0.0/0`; `source_ranges` restricts only the dedicated
CA host. Restrict the security-group rules in the Terraform code or apply
account-level controls before using this module outside a disposable test
environment.

## Destroy

Destroy with the same variables used for the apply:

```bash
terraform destroy
# Or: terraform destroy -var-file=rs.tfvars
```

The backup bucket uses `force_destroy`, so destroying the deployment also deletes
its backup objects. Remove generated inventory and SSH files after destruction if
they are no longer needed.

## Expanding existing deployments

Supported scale-out changes are additive only:

- Increase `shard_count` to add shards to an existing sharded cluster.
- Increase `data_nodes_per_replset` to add data-bearing members to a standalone replica set.
- Add a new sharded cluster or standalone replica set.

After editing variables, run `terraform apply` to create the new instances and
regenerate inventory files. Then run the matching Ansible scale-out playbook from
the repository root:

```bash
ansible-playbook -i terraform/aws/myenv_inventory_cl01 ansible/add_shard.yml \
  --extra-vars "new_shard_group=shard3"

ansible-playbook -i terraform/aws/myenv_inventory_rs01 ansible/add_replset_member.yml \
  --extra-vars "target_replset=rs01"
```

For an entirely new cluster or replica set, run `ansible/main.yml` against its
generated inventory. Reducing topology size, changing `configsvr_count`, changing
`shardsvr_replicas`, and changing arbiter counts are not implemented.
