# Deploy MongoDB infrastructure on AWS

This Terraform module creates:

- VPC
- subnets
- internet gateway
- firewall rules
- EC2 instances for MongoDB components
- EBS volumes for data-bearing members
- S3 bucket for backups
- generated Ansible inventory files
- generated SSH configuration

## Prerequisites

1. Install [Terraform](https://developer.hashicorp.com/terraform/downloads) 1.0+.
2. Install [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
3. Authenticate in your shell when running Terraform manually:

```bash
aws configure
```

If you use the Web UI, configure an AWS access key in UI Settings instead. The UI writes isolated AWS credential/config files under `ui-go/secrets/cloud/aws/` and passes them to Terraform with `AWS_SHARED_CREDENTIALS_FILE`, `AWS_CONFIG_FILE`, and `AWS_PROFILE`.

4. Change into this directory:

```bash
cd mongo_terraform_ansible/terraform/aws
```

5. Initialize Terraform:

```bash
terraform init
```

## Quick Start

1. Review `variables.tf` and adjust the values you need.
2. Create the infrastructure:

```bash
terraform apply
```

3. Append the generated SSH config to your local SSH config if desired:

```bash
cat ssh_config* >> ~/.ssh/config
```

4. Optionally copy the generated inventories into [`../../ansible`](../../ansible):

```bash
cp inventory* ../../ansible/
```

5. Run the Ansible playbooks from [`../../ansible`](../../ansible) to install and configure MongoDB.

Typical Terraform provisioning time for a 2-shard cluster is about 1 minute.

Use `terraform output -json` to inspect generated S3 backup credentials.

## Connecting

If you merged the generated SSH config into `~/.ssh/config`, you can connect by host alias:

```bash
ssh my-cluster-name-mongodb-cfg01
```

## Key Variables

- `prefix`: resource name prefix; change it to avoid collisions
- `clusters`: sharded clusters to provision; rename the default entry before deploying
- `replsets`: standalone replica sets to provision
- `my_ssh_user`: local SSH username used when generating `ssh_config`
- `ssh_public_key_path`: public key added to `authorized_keys` on created instances
- `enable_ycsb`: optional dedicated YCSB workload generator instance
- `enable_audit` and `audit_filter`: optional per-cluster or per-replset PSMDB audit settings inside `clusters` or `replsets`

## Expanding Existing Deployments

Supported scale-out changes are additive only:

- Increase `shard_count` to add shards to an existing sharded cluster.
- Increase `data_nodes_per_replset` to add data-bearing members to an existing standalone replica set.
- Add a new sharded cluster or standalone replica set.

After editing variables, run `terraform apply` to create the new instances and regenerate inventory files. For added shards or replica set members, run the matching Ansible scale-out playbook from the repository root:

```bash
ansible-playbook -i terraform/aws/<prefix>_inventory_<cluster> ansible/add_shard.yml \
  --extra-vars "new_shard_group=shard<N>"

ansible-playbook -i terraform/aws/<prefix>_inventory_<rs> ansible/add_replset_member.yml \
  --extra-vars "target_replset=<rs>"
```

For entirely new clusters or replica sets, run `ansible/main.yml` against their generated inventory.

Reducing topology size, changing `configsvr_count`, changing `shardsvr_replicas`, and changing arbiter counts are not implemented.
