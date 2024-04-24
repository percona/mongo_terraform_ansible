# Deploy hardware for MongoDB clusters using Terraform in Google Cloud
## Quick guide
0. Upload your SSH key to GCP
    Login to Google Cloud console, go to Compute Engine -> Metadata. Select the SSH keys tab and click the Edit button. Upload your public SSH key and write down the associated username. This will be used to login to the instances created.
1. Clone this repository on your machine and cd to the directory
2. Install Google Cloud SDK https://cloud.google.com/sdk/docs/install#linux
3. Run `gcloud auth application-default login` to authenticate
4. Run `terraform init`
5. Edit the file `variables.tf` (see below)
6. Run `terraform apply` to provision the hardware. Choose the project where you are working on if prompted
7. Copy the auto-generated Ansible inventory to ./ansible folder
8. Append the auto-generated SSH configuration (ssh_config file) to your ~/.ssh/config to connect easily. Modify as needed depending on your environment.

Look inside the `ansible` folder for instructions to complete the deployment of a complete MongoDB cluster

The deployment of the resources required for a 2 shard cluster takes around 1 minute

You can run `terraform output -json` to see the access/secret keys generated for the Cloud Storage bucket created to store backups

## Minimum variables to customize
These are the ones you have to care about for a quick deploy with default values:
- project_id
    This is the GCP project to use 
- env_tag
    This is just a prefix for the name of your environment. Make sure nobody else is using the same one in the project
- gce_ssh_users
    List of SSH usernames and path to their public keys to configure access to your instances
- my_ssh_user
    Your own SSH user. This is used to generate an SSH config file for you
- enable_ssh_gateway
    Wether you can SSH directly or through a jump host. This is used to generate an SSH config file for you
