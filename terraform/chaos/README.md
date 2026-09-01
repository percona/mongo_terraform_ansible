# Deploy MongoDB infrastructure with the CHAOS provider

Percona ClusterSync is disabled by default. Set `enable_pcsm=true` to create one dedicated 2-vCPU/4-GB VM in the environment network. Only SSH is allowed inbound; API port `2242` is not exposed. Generated inventories and SSH configuration expose `${prefix}-pcsm`. Supply an already-generated secure environment file to Ansible through `pcsm_env_file_source`; Terraform never receives its contents. The package version defaults to `pcsm_version="0.9.0"`.

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
