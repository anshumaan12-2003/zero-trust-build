# The Azure cluster

One small Ubuntu VM running k3s, reachable only from your own IP address. CI checks this Terraform on every change (`cluster.yml`) but never applies it, because applying spends real credit.

## Before you create anything

1. **Set a subscription budget in the portal** (Cost Management, then Budgets), with an email alert at a low amount. The budget in `main.tf` covers only this resource group, so it can't catch anything created elsewhere.
2. **Check the price.** The default `Standard_B2ms` (2 CPUs, 8 GB) costs a few US cents an hour. Check the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/) for your region. The public IP and disk cost a little too, even while the VM is stopped.
3. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill it in. Git ignores `*.tfvars`.

## One session

```bash
az login
terraform -chdir=terraform init
terraform -chdir=terraform apply
```

After about 3 minutes k3s is up. Fetch the kubeconfig with the command that `terraform output get_kubeconfig` prints, then set up the cluster exactly as CI does:

```bash
export KUBECONFIG=~/.kube/ztb-k3s.yaml
cluster/install.sh main
cluster/check-cluster.sh main
```

To see the dashboard, run `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80` and open `http://localhost:3000`. The admin password is in the `kube-prometheus-stack-grafana` secret.

## Always finish with

```bash
terraform -chdir=terraform destroy
```

A forgotten VM keeps using your credit. Everything is in one resource group, so destroy removes all of it.

## What it creates

| Resource | Why |
|---|---|
| Resource group | Holds everything, so one destroy removes it all |
| Budget on the resource group | Emails at 50% of actual spend and 100% of forecast spend. Created before the VM |
| Virtual network and subnet | A private network for the VM |
| Network security group | Allows SSH (22) and the Kubernetes API (6443) from `admin_cidr` only. Azure denies all other inbound traffic by default |
| Static public IP | Lets the k3s API certificate include the address |
| Ubuntu 24.04 VM | Runs k3s, installed on first boot by `cloud-init.yaml.tftpl` from a pinned release |

`admin_cidr` must be a single `/32` address. The variable check refuses ranges such as `0.0.0.0/0`.
