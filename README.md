# Deploy hardware for MongoDB clusters using Terraform in Google Cloud
## Quick guide
1. Clone this repository on your machine
2. Install Google Cloud SDK https://cloud.google.com/sdk/docs/install#linux
3. Run `gcloud auth application-default login` to authenticate
4. Run `terraform init`
5. Edit the file `percona-variables.tf` to configure the number of shards, etc.
6. Edit the file `variables.tf` to configure the project ID and the region
7. Run `terraform plan` and choose the project where you are working on 
8. Run `terraform apply` to provision the hardware
9. Look inside `ansible` folder for instructions to deploy MongoDB (Optional)

Note: any output marked as `secret` can be viewed by running `terraform output -json`
