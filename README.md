# Deploy hardware for MongoDB clusters using Terraform in Google Cloud
## Quick guide
1. Clone this repo on your machine
2. Install Google Cloud SDK https://cloud.google.com/sdk/docs/install#linux
3. Run `gcloud auth application-default login` to authenticate
4. Run `terraform init` and pick the bucket to store Terraform info
5. Edit the file `percona-variables.tf` to configure the number of shards, etc.
6. Run `terraform plan` and choose the project where you are working on 
7. Run `terraform apply` to provision the hardware
