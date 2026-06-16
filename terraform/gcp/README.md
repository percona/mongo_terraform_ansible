# Deploy MongoDB infrastructure on Google Cloud

This Terraform module creates:

- VPC and subnets
- firewall rules
- VM instances for MongoDB components
- persistent disks for data-bearing members
- Cloud Storage bucket for backups
- generated Ansible inventory files
- generated SSH configuration

## Prerequisites

1. Install [Terraform](https://developer.hashicorp.com/terraform/downloads) 1.0+.
2. Install the [Google Cloud SDK](https://cloud.google.com/sdk/docs/install).
3. Authenticate in your shell:

```bash
gcloud auth application-default login
```

4. Change into this directory:

```bash
cd mongo_terraform_ansible/terraform/gcp
```

5. Initialize Terraform:

```bash
terraform init
```

## Quick Start

1. Review `variables.tf` and update the values you need.
2. Create the infrastructure:

```bash
terraform apply
```

3. Append the generated SSH config if you want host aliases locally:

```bash
cat ssh_config* >> ~/.ssh/config
```

4. Optionally copy generated inventories into [`../../ansible`](../../ansible):

```bash
cp inventory* ../../ansible/
```

5. Run the Ansible playbooks from [`../../ansible`](../../ansible) to complete the software installation.

Typical Terraform provisioning time for a 2-shard cluster is about 1 minute.

Use `terraform output -json` to inspect generated Cloud Storage credentials.

## Connecting

If you merged the generated SSH config into `~/.ssh/config`, connect by host alias:

```bash
ssh my-cluster-name-mongodb-cfg01
```

## Key Variables

- `prefix`: resource name prefix; change it to avoid collisions
- `project_id`: GCP project where resources will be created
- `clusters`: sharded clusters to provision; rename the default entry before deploying
- `replsets`: standalone replica sets to provision
- `gce_ssh_users`: map of SSH usernames to public key files
- `my_ssh_user`: local SSH username used when generating `ssh_config`
- `enable_audit` and `audit_filter`: optional per-cluster or per-replset PSMDB audit settings inside `clusters` or `replsets`

## Expanding Existing Deployments

Supported scale-out changes are additive only:

- Increase `shard_count` to add shards to an existing sharded cluster.
- Increase `data_nodes_per_replset` to add data-bearing members to an existing standalone replica set.

After editing variables, run `terraform apply` to create the new instances and regenerate inventory files. Then run the matching Ansible playbook from the repository root:

```bash
ansible-playbook -i terraform/gcp/<prefix>_inventory_<cluster> ansible/add_shard.yml \
  --extra-vars "new_shard_group=shard<N>"

ansible-playbook -i terraform/gcp/<prefix>_inventory_<rs> ansible/add_replset_member.yml \
  --extra-vars "target_replset=<rs>"
```

Reducing topology size, changing `configsvr_count`, changing `shardsvr_replicas`, and changing arbiter counts are not implemented.
