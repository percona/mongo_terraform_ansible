# Deploy MongoDB infrastructure on Azure

This Terraform module creates:

- a resource group, virtual network, subnet, and network security groups
- public IP addresses and network interfaces
- Linux virtual machines and managed disks for MongoDB and optional supporting services
- a Storage account, private backup container, and lifecycle policy
- generated Ansible inventory and SSH configuration files

## Prerequisites

- Terraform 1.9 or newer
- Ansible and OpenSSH
- an existing SSH key pair
- an Azure subscription
- an administrator who can register resource providers, create an application and
  service principal, and assign a subscription role

Install the local tools and Azure CLI from the repository root:

```bash
./scripts/install-prerequisites.sh --azure
```

## Create the Azure deployment service principal

This Terraform root creates its own resource group, so the deployment identity
needs permission at subscription scope. Run these bootstrap commands as a user
with permission to create service principals and role assignments.

1. Log in, select the subscription, and register the resource providers used by
   this module:

```bash
az login
export SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
az account set --subscription "$SUBSCRIPTION_ID"

az provider register --namespace Microsoft.Compute --wait
az provider register --namespace Microsoft.Network --wait
az provider register --namespace Microsoft.Storage --wait
```

2. Create the service principal and grant it `Contributor` on the subscription:

```bash
export SP_NAME=mongodb-terraform-deployer
az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role Contributor \
  --scopes "/subscriptions/$SUBSCRIPTION_ID"
```

Save the returned `appId`, `password`, and `tenant` in your approved secret
manager. The password is displayed only when it is created. `Contributor` is
required to create and destroy the resource group, networking, compute, disks,
public IPs, and Storage resources and to read the Storage account key used by
PBM. Terraform does not create Azure role assignments.

3. Authenticate as the service principal and export the variables used by the
   AzureRM provider:

```bash
export ARM_CLIENT_ID="00000000-0000-0000-0000-000000000000"
export ARM_CLIENT_SECRET="replace-with-the-service-principal-password"
export ARM_TENANT_ID="00000000-0000-0000-0000-000000000000"
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

az login --service-principal \
  --username "$ARM_CLIENT_ID" \
  --password "$ARM_CLIENT_SECRET" \
  --tenant "$ARM_TENANT_ID"
az account set --subscription "$ARM_SUBSCRIPTION_ID"
az account show --query '{subscription:id, tenant:tenantId, user:user.name}'
```

For the Web UI, enter the client ID, client secret, tenant ID, and subscription ID
in **Settings**. The UI stores the secret under `ui-go/secrets/cloud/azure/`, uses
an isolated Azure CLI configuration, and sets `ARM_CLIENT_ID`,
`ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, and `ARM_SUBSCRIPTION_ID` for Terraform.

Interactive `az login` authentication also works for manual Terraform usage.

## Configure the deployment

Change into the Azure Terraform directory:

```bash
cd terraform/azure
```

Review `variables.tf`, then put overrides in `terraform.tfvars` or another tfvars
file. At minimum, review:

- `prefix`, `location`, `default_resource_group_name`, `clusters`, and `replsets`
- `ssh_users`, `ssh_private_key_path`, and `my_ssh_user`
- VM sizes, image, managed-disk sizes, and `use_spot_instances`
- the `prefix` used in the globally unique Storage account name and `backup_retention`
- `source_ranges` for inbound access
- optional PMM, CA/TLS, LDAP, and YCSB settings

Azure Storage account names are globally unique and have strict length and
character limits. Choose a short, unique `prefix` containing letters and numbers.

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

Azure does not create a separate PBM service principal. Terraform retrieves the
created Storage account's primary key and writes it into each generated inventory.
Inspect outputs when needed with:

```bash
terraform output -json
```

The service-principal secret and Storage account key are sensitive. The Storage
key is stored in Terraform state and generated inventory files. Keep secrets,
state, tfvars, inventories, SSH configuration, and UI secret directories out of
source control and restrict their filesystem permissions.

## Network security

Instances receive public IP addresses. The default `source_ranges` value is
`0.0.0.0/0`, and ICMP is publicly allowed. Before deployment, restrict SSH source
ranges to trusted addresses and review all network security group rules. The
defaults are intended for disposable test environments, not production.

## Destroy

Destroy with the same variables used for the apply:

```bash
terraform destroy
# Or: terraform destroy -var-file=my-deployment.tfvars
```

Destroying the resource group removes all resources, including the backup Storage
account and its data. Remove generated inventory and SSH files after destruction
if they are no longer needed.

## Expanding existing deployments

Supported scale-out changes are additive only:

- Increase `shard_count` to add shards to an existing sharded cluster.
- Increase `data_nodes_per_replset` to add data-bearing members to a standalone replica set.
- Add a new sharded cluster or standalone replica set.

After editing variables, run `terraform apply` to create the new instances and
regenerate inventory files. Then run the matching Ansible scale-out playbook from
the repository root:

```bash
ansible-playbook -i terraform/azure/myenv_inventory_cl01 ansible/add_shard.yml \
  --extra-vars "new_shard_group=shard3"

ansible-playbook -i terraform/azure/myenv_inventory_rs01 ansible/add_replset_member.yml \
  --extra-vars "target_replset=rs01"
```

For an entirely new cluster or replica set, run `ansible/main.yml` against its
generated inventory. Reducing topology size, changing `configsvr_count`, changing
`shardsvr_replicas`, and changing arbiter counts are not implemented.
