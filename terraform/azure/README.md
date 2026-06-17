# Deploy MongoDB infrastructure on Azure

This Terraform module creates:

- virtual network and subnet
- network security groups
- virtual machines for MongoDB components
- managed disks for data-bearing members
- storage account and container for backups
- generated Ansible inventory files
- generated SSH configuration

## Prerequisites

1. Install [Terraform](https://developer.hashicorp.com/terraform/downloads) 1.0+.
2. Install [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli).
3. Log in:

```bash
az login
```

4. Change into this directory:

```bash
cd mongo_terraform_ansible/terraform/azure
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

Use `terraform output -json` to inspect generated backup storage credentials.

## Connecting

If you merged the generated SSH config into `~/.ssh/config`, connect by host alias:

```bash
ssh my-cluster-name-mongodb-cfg01
```

## Key Variables

- `prefix`: resource name prefix; change it to avoid collisions
- `clusters`: sharded clusters to provision; rename the default entry before deploying
- `replsets`: standalone replica sets to provision
- `ssh_users`: map of SSH usernames to public key files
- `my_ssh_user`: local SSH username used when generating `ssh_config`
- `enable_ycsb`: optional dedicated YCSB workload generator instance
- `enable_audit` and `audit_filter`: optional per-cluster or per-replset PSMDB audit settings inside `clusters` or `replsets`

## Expanding Existing Deployments

Supported scale-out changes are additive only:

- Increase `shard_count` to add shards to an existing sharded cluster.
- Increase `data_nodes_per_replset` to add data-bearing members to an existing standalone replica set.
- Add a new sharded cluster or standalone replica set.

After editing variables, run `terraform apply` to create the new instances and regenerate inventory files. For added shards or replica set members, run the matching Ansible scale-out playbook from the repository root:

```bash
ansible-playbook -i terraform/azure/<prefix>_inventory_<cluster> ansible/add_shard.yml \
  --extra-vars "new_shard_group=shard<N>"

ansible-playbook -i terraform/azure/<prefix>_inventory_<rs> ansible/add_replset_member.yml \
  --extra-vars "target_replset=<rs>"
```

For entirely new clusters or replica sets, run `ansible/main.yml` against their generated inventory.

Reducing topology size, changing `configsvr_count`, changing `shardsvr_replicas`, and changing arbiter counts are not implemented.
