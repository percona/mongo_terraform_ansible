# Deploy MongoDB infrastructure on Google Cloud

This Terraform module creates:

- a custom VPC, regional subnet, and firewall rules
- Compute Engine instances and persistent disks for MongoDB and optional supporting services
- a Cloud Storage backup bucket and lifecycle rule
- a PBM service account, HMAC key, and bucket IAM binding
- generated Ansible inventory and SSH configuration files

## Prerequisites

- Terraform 1.9 or newer
- Ansible and OpenSSH
- an existing SSH key pair
- a Google Cloud project with billing enabled
- a project administrator who can enable APIs, create service accounts and keys,
  and grant project IAM roles

Install the local tools and Google Cloud CLI from the repository root:

```bash
./scripts/install-prerequisites.sh --gcp
```

## Create the GCP deployment service account

Run the following bootstrap commands as a project administrator. Replace the
project ID and choose a unique service-account name if necessary.

1. Select the project and enable the APIs used by the Terraform resources:

```bash
export PROJECT_ID=my-gcp-project
export DEPLOY_SA=mongodb-terraform-deployer

gcloud config set project "$PROJECT_ID"
gcloud services enable \
  compute.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  --project "$PROJECT_ID"
```

2. Create the deployment service account:

```bash
gcloud iam service-accounts create "$DEPLOY_SA" \
  --display-name="MongoDB Terraform deployer" \
  --project "$PROJECT_ID"

export DEPLOY_SA_EMAIL="${DEPLOY_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
```

3. Grant the project roles required by the resources in this module:

```bash
for role in \
  roles/browser \
  roles/compute.admin \
  roles/storage.admin \
  roles/iam.serviceAccountAdmin \
  roles/storage.hmacKeyAdmin
do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${DEPLOY_SA_EMAIL}" \
    --role="$role"
done
```

These roles let Terraform inspect the project; create networks, firewalls,
instances, and disks; create the backup bucket and IAM binding; and create the
separate PBM service account and HMAC key. If organizational policy prohibits
service-account keys or requires custom roles, use an approved workload identity
with equivalent permissions for manual Terraform runs. The Web UI currently
requires a service-account JSON key.

4. Create a JSON key in a protected location and authenticate:

```bash
gcloud iam service-accounts keys create "$HOME/.config/gcloud/mongodb-terraform.json" \
  --iam-account="$DEPLOY_SA_EMAIL" \
  --project "$PROJECT_ID"

export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcloud/mongodb-terraform.json"
gcloud auth activate-service-account "$DEPLOY_SA_EMAIL" \
  --key-file="$GOOGLE_APPLICATION_CREDENTIALS" \
  --project="$PROJECT_ID"
gcloud auth list --filter=status:ACTIVE
gcloud auth print-access-token >/dev/null
```

For the Web UI, upload this JSON key and enter `PROJECT_ID` in **Settings**. The
UI stores the key under `ui-go/secrets/cloud/gcp/`, uses an isolated Cloud SDK
configuration, and sets `GOOGLE_APPLICATION_CREDENTIALS` for Terraform.

For an interactive manual deployment, Application Default Credentials also work:

```bash
gcloud auth application-default login
```

## Configure the deployment

Change into the GCP Terraform directory:

```bash
cd terraform/gcp
```

Review `variables.tf`, then put overrides in `terraform.tfvars` or another tfvars
file. At minimum, review:

- `project_id`, `prefix`, `region`, `clusters`, and `replsets`
- `gce_ssh_users`, `ssh_private_key_path`, and `my_ssh_user`
- machine types, image, disk sizes, and `use_spot_instances`
- backup bucket naming and retention
- `source_ranges` for inbound access
- optional PMM, CA/TLS, LDAP, and YCSB settings

Resource names must be unique in the project. Some firewall names are fixed, so
deploying multiple copies of this Terraform root in one project can cause naming
collisions even when `prefix` differs.

## Deploy

Initialize and review the Terraform plan before applying it:

```bash
terraform init
terraform plan
terraform apply
```

When using a non-default variable file, pass it consistently:

```bash
terraform plan -var-file=my-deployment.tfvars
terraform apply -var-file=my-deployment.tfvars
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

Terraform creates a separate PBM service account named
`<prefix>-mongo-backup-sa`, grants it access to the created bucket, and creates
an HMAC key. This is not the deployment service account. Inspect outputs with:

```bash
terraform output -json
```

The JSON deployment key and PBM HMAC secret are sensitive. The PBM secret is
stored in Terraform state and generated inventory files. Keep keys, state,
tfvars, inventories, SSH configuration, and UI secret directories out of source
control and restrict their filesystem permissions.

## Network security

Instances receive public IP addresses. The default `source_ranges` value is
`0.0.0.0/0`, and ICMP is publicly allowed. Before deployment, restrict SSH source
ranges to trusted addresses and review all firewall rules. The defaults are
intended for disposable test environments, not production.

## Destroy

Destroy with the same variables used for the apply:

```bash
terraform destroy
# Or: terraform destroy -var-file=my-deployment.tfvars
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
ansible-playbook -i terraform/gcp/myenv_inventory_cl01 ansible/add_shard.yml \
  --extra-vars "new_shard_group=shard3"

ansible-playbook -i terraform/gcp/myenv_inventory_rs01 ansible/add_replset_member.yml \
  --extra-vars "target_replset=rs01"
```

For an entirely new cluster or replica set, run `ansible/main.yml` against its
generated inventory. Reducing topology size, changing `configsvr_count`, changing
`shardsvr_replicas`, and changing arbiter counts are not implemented.
