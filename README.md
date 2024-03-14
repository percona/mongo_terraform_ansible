# Deploy hardware for MongoDB clusters using Terraform in Google Cloud
## Quick guide
0. Login to Google Cloud console, go to Compute Engine -> Metadata. Select the SSH keys tab and click the Edit button. Upload your public SSH key and write down the associated username. This will be used for login into the instances
1. Clone this repository on your machine
2. Install Google Cloud SDK https://cloud.google.com/sdk/docs/install#linux
3. Run `gcloud auth application-default login` to authenticate
4. Run `terraform init`
5. Edit the file `percona-variables.tf` to configure the environment name (make sure this is unique), instance types, number of shards, AMI to use, etc.
6. Edit the file `variables.tf` to configure the GCP project ID, the region, and SSH user and key to login to the created instances
7. Run `terraform plan` and choose the project where you are working on if prompted
8. Run `terraform apply` to provision the hardware
9. Copy the auto-generated Ansible inventory to ./ansible folder
10. Append the auto-generated SSH configuration (ssh_config file) to ~/.ssh/config to connect to the hosts via a bastion server. Modify as needed depending on your environment.

Look inside the `ansible` folder for instructions to complete the deploy of a MongoDB cluster (Optional)

The deployment of the resources required for a 2 shard cluster takes around 1 minute

You can run `terraform output -json` to see the access/secret keys generated for the created Cloud Storage bucket 
