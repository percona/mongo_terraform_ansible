# Deploy MongoDB infrastructure with the CHAOS provider

Percona ClusterSync is disabled by default. Set `enable_pcsm=true` to create one dedicated 2-vCPU/4-GB VM in the environment network. Only SSH is allowed inbound; API port `2242` is not exposed. Terraform never receives PCSM connection URIs or passwords. The package version defaults to `pcsm_version="0.9.0"`.

## Percona ClusterSync

Set source and target kinds to `cluster` or `replset`; they must match and the names must differ. Terraform writes one normal inventory per topology plus `<prefix>_inventory_pcsm`. The PCSM inventory contains only `pcsm-source`, `pcsm-target`, and `[pcsm]`, so it cannot alter MongoDB replica-set membership.

For a manual deployment, run `main.yml` once for every selected topology after `terraform apply`, then run `pcsm.yml` once:

```bash
ansible-playbook -i myenv_inventory_rs-source ../../ansible/main.yml
ansible-playbook -i myenv_inventory_rs-target ../../ansible/main.yml
ansible-playbook -i myenv_inventory_pcsm ../../ansible/pcsm.yml \
  -e pcsm_env_file_source="$HOME/.config/mongodeploy/myenv-pcsm.env"
```

Create the environment file before the final command with owner-only permissions. Use URL-encoded passwords in the URI; hexadecimal passwords generated below are already URL-safe. Replace the member placeholders with the private MongoDB hostnames listed in the generated source and target topology inventories.

```bash
mkdir -p "$HOME/.config/mongodeploy"
umask 077
source_password="$(openssl rand -hex 24)"
target_password="$(openssl rand -hex 24)"
cat >"$HOME/.config/mongodeploy/myenv-pcsm.env" <<EOF
PCSM_SOURCE_URI='mongodb://pcsm-source:${source_password}@source-member-0:27017,source-member-1:27017/?authSource=admin&appName=pcsm&replicaSet=rs-source'
PCSM_TARGET_URI='mongodb://pcsm-target:${target_password}@target-member-0:27017,target-member-1:27017/?authSource=admin&appName=pcsm&replicaSet=rs-target'
PCSM_SOURCE_PASSWORD='${source_password}'
PCSM_TARGET_PASSWORD='${target_password}'
EOF
chmod 600 "$HOME/.config/mongodeploy/myenv-pcsm.env"
```

Creates the following resources:

- VM instances for each MongoDB component (using the `chaos` provider)
- A dedicated VM running [Minio](https://min.io/) for S3-compatible backup storage
- Firewall rules per instance
- Ansible inventory
- SSH configuration

Unlike public cloud providers (AWS, GCP, Azure), the CHAOS provider does not offer managed object storage. A Minio server VM is provisioned instead to provide an S3-compatible backup endpoint for [Percona Backup for MongoDB (PBM)](https://docs.percona.com/percona-backup-mongodb/index.html).

## Prerequisites

1. From the repository root, install Terraform and Ansible:

   ```bash
   ./scripts/install-prerequisites.sh
   ```

2. Ensure the privately distributed `percona/chaos` Terraform provider is available
   in the standard Terraform plugin directory. The installer cannot obtain this provider.

3. Change into this directory

    ```
    cd mongo_terraform_ansible/terraform/chaos
    ```

4. Initialize Terraform

    ```
    terraform init
    ```

## Quick Start

1. Review `variables.tf` and adjust the values you need.

    ```
    vi variables.tf
    ```

2. Run Terraform to create the resources

    ```
    terraform apply
    ```

### Minimum PCSM tfvars

This minimal example creates two PSMDB replica sets and a PCSM VM. Export `CHAOS_API_TOKEN` before running Terraform and set `my_ssh_user` to your CHAOS user. SSH key management is handled by CHAOS.
Save it as `pcsm.tfvars` and pass `-var-file=pcsm.tfvars` to `terraform plan` and `terraform apply`.

```hcl
prefix      = "myenv"
my_ssh_user = "your_chaos_username"

clusters   = {}
enable_pmm = false

replsets = {
  "rs-source" = { enable_pmm = false, enable_pbm = false }
  "rs-target" = { enable_pmm = false, enable_pbm = false }
}

enable_pcsm      = true
pcsm_source_kind = "replset"
pcsm_source_name = "rs-source"
pcsm_target_kind = "replset"
pcsm_target_name = "rs-target"
```

3. Append the generated SSH configuration locally if desired:

    ```
    cat ssh_config* >> ~/.ssh/config
    ```

4. (Optional) Copy the generated inventories to the [ansible](../../ansible) folder

    ```
    cp inventory* ../../ansible/
    ```

5. Run the Ansible playbooks from [../../ansible](../../ansible) to complete the software installation.

- You can run `terraform output` to see the Minio endpoint and credentials generated for backup storage

## Connecting

If you copied the generated configuration to ssh_config, no parameters should be needed. Example:

```
    ssh my-cluster-name-mongodb-cfg00
```

## Key Variables

Review these first before deploying:

- **prefix**

    Prefix to be applied to the resources created, change it to avoid collisions with other users environments

- **clusters**

    By default we deploy 1 sharded cluster, but more can be added. Make sure to change the default name to avoid duplicates. The configuration for each cluster can be customized by adding the optional values listed.

- **replsets**

    If you want to provision any replica sets (non-sharded), set this variable. Make sure to change the default name to avoid duplicates.

- **my_ssh_user**

    Your own SSH user name. This is used to generate an SSH config file for you to login easily.
    SSH key management is handled automatically by the CHAOS platform — no public key injection is needed.

- **delete_after_days**

    Number of days before instances are automatically deleted (default: 14). Useful for temporary lab environments.

- **enable_ycsb**

    Optional dedicated YCSB workload generator instance.

- **enable_audit** and **audit_filter**

    Optional per-cluster or per-replset PSMDB audit settings inside `clusters` or `replsets`.

## Expanding Existing Deployments

Supported scale-out changes are additive only:

- Increase `shard_count` to add shards to an existing sharded cluster.
- Increase `data_nodes_per_replset` to add data-bearing members to an existing standalone replica set.
- Add a new sharded cluster or standalone replica set.

After editing variables, run `terraform apply` to create the new instances and regenerate inventory files. For added shards or replica set members, run the matching Ansible scale-out playbook from the repository root:

```bash
ansible-playbook -i terraform/chaos/<prefix>_inventory_<cluster> ansible/add_shard.yml \
  --extra-vars "new_shard_group=shard<N>"

ansible-playbook -i terraform/chaos/<prefix>_inventory_<rs> ansible/add_replset_member.yml \
  --extra-vars "target_replset=<rs>"
```

For entirely new clusters or replica sets, run `ansible/main.yml` against their generated inventory.

Reducing topology size, changing `configsvr_count`, changing `shardsvr_replicas`, and changing arbiter counts are not implemented.

## Backup Storage (Minio)

Since the CHAOS environment does not feature managed object storage, a dedicated VM running [Minio](https://min.io/) is provisioned as an S3-compatible alternative to AWS S3 or GCP Cloud Storage.

The Minio server:
- Listens on port `9000` (API) and `9001` (web console)
- Uses root credentials defined by `minio_root_user` and `minio_root_password` variables
- Is **installed and configured via Ansible** (`minio_install.yml` playbook) — the Terraform `user_data` only sets the hostname
- Automatically creates the backup bucket during Ansible provisioning
- Is referenced in the generated Ansible inventory as the `endpointUrl` for PBM with `storage_provider=minio`

To access the Minio web console, use SSH port forwarding:

```
ssh -L 9001:localhost:9001 <minio-server-hostname>
```

Then open `http://localhost:9001` in your browser.
