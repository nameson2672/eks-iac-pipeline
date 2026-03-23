# EKS IaC Pipeline

> Fully automated, production-pattern Amazon EKS cluster provisioned with Terraform — custom VPC, private worker nodes, remote state, and a CI pipeline that validates every change before it can be applied.

---
![diagram](https://github.com/nameson2672/eks-iac-pipeline/blob/main/public/diagram.png?raw=true)

## Overview

This project automates the end-to-end provisioning of a Kubernetes cluster on AWS. It is structured to match real-world practices: infrastructure is split into reusable modules, state is stored remotely with locking, every pull request runs a full `terraform plan` and surfaces the result as a comment, and no one can apply to production without passing through CI first.

**Resources provisioned by a single `terraform apply`:**

- **VPC** — `10.0.0.0/16` with two public subnets and two private subnets across two availability zones
- **Internet Gateway** — attached to the VPC for public-subnet egress
- **NAT Gateway** — sits in the first public subnet; all worker node outbound traffic routes through it
- **Route tables** — public routes to the IGW, private routes to the NAT Gateway
- **EKS control plane** — Kubernetes 1.30, hosted and managed by AWS
- **Managed node group** — `t3.medium` EC2 instances running in the private subnets, autoscaling 1–3 nodes
- **IAM roles** — cluster role (trusts `eks.amazonaws.com`) and node role (trusts `ec2.amazonaws.com`) with minimum required policies
- **OIDC provider** — registered at cluster creation so workloads can assume IAM roles immediately (IRSA)
- **Security groups** — explicit ingress/egress rules between the control plane and nodes
- **S3 + DynamoDB** — remote state backend with encryption and concurrency locking

---


### Networking rules

| Traffic | From | To | Port |
| --- | --- | --- | --- |
| API server access | Worker nodes | Control plane | 443 |
| Kubelet / exec / logs | Control plane | Worker nodes | 10250 |
| Port-forward tunnels | Control plane | Worker nodes | 1025–65535 |
| Node-to-node (pod mesh) | Node SG | Node SG | All |
| Outbound (ECR, AWS APIs) | Worker nodes | NAT Gateway | All |

---

## Prerequisites

### Tools

| Tool | Minimum version | Install |
| --- | --- | --- |
| Terraform | >= 1.14.7 | [terraform.io/downloads](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | >= 2.x | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| kubectl | >= 1.30 | [kubernetes.io/docs](https://kubernetes.io/docs/tasks/tools/) |
| Git | any | [git-scm.com](https://git-scm.com/) |

### AWS resources (one-time setup, outside Terraform)

These must exist before the first `terraform init`. Create them once per AWS account:

```bash
# 1. S3 bucket for Terraform state (versioning + encryption recommended)
aws s3api create-bucket \
  --bucket eks-iac-tf-state \
  --region ca-central-1 \
  --create-bucket-configuration LocationConstraint=ca-central-1

aws s3api put-bucket-versioning \
  --bucket eks-iac-tf-state \
  --versioning-configuration Status=Enabled

# 2. DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ca-central-1
```

### AWS credentials

Configure credentials locally before running any Terraform command:

```bash
aws configure
# AWS Access Key ID:     <your key>
# AWS Secret Access Key: <your secret>
# Default region:        ca-central-1
# Default output format: json
```

---

## Repository Structure

```text
eks-iac-pipeline/
│
├── main.tf            # Root: wires the VPC and EKS modules together
├── variables.tf       # Root variable declarations
├── outputs.tf         # Surfaces cluster endpoint, VPC ID, OIDC ARN, etc.
├── provider.tf        # AWS + TLS provider versions (>= 1.14.7)
├── backend.tf         # S3 remote state + DynamoDB lock configuration
├── dev.tfvars         # Variable values for the dev environment
│
├── modules/
│   │
│   ├── vpc/
│   │   ├── main.tf        # VPC, IGW, public/private subnets, NAT Gateway,
│   │   │                  # route tables, Kubernetes subnet tags
│   │   ├── variable.tf    # name, vpc_cidr, AZs, subnet CIDRs, cluster_name, …
│   │   └── output.tf      # vpc_id, subnet ID maps and lists, NAT IP, …
│   │
│   └── eks/
│       ├── main.tf        # EKS cluster, managed node group, IAM roles,
│       │                  # security groups, OIDC provider
│       ├── variable.tf    # name, subnet_ids, version, node sizing, …
│       └── output.tf      # cluster_name, endpoint, CA data, OIDC ARN, …
│
└── .github/
    └── workflows/
        ├── validate.yaml  # Automatic CI on every push and PR
        └── terraform.yml  # Manual apply / destroy via workflow_dispatch
```

**Key relationships:**

- `main.tf` calls `module.vpc` first, then passes `module.vpc.vpc_id` and `module.vpc.private_subnet_ids_list` into `module.eks`
- The EKS module depends on the VPC module via an explicit `depends_on`
- Both modules expose outputs that are re-exported by the root `outputs.tf`

---

## Running Locally

### 1. Clone and initialise

```bash
git clone https://github.com/<your-username>/eks-iac-pipeline.git
cd eks-iac-pipeline

# Downloads providers (hashicorp/aws, hashicorp/tls) and connects to S3 backend
terraform init
```

### 2. Review the plan

```bash
terraform plan -var-file=dev.tfvars
```

The plan shows every resource that will be created. Review it carefully — especially IAM roles and security group rules — before applying.

### 3. Apply

```bash
terraform apply -var-file=dev.tfvars
```

Provisioning takes approximately 15–20 minutes. EKS control plane creation accounts for most of that time.

### 4. Connect kubectl

```bash
aws eks update-kubeconfig \
  --region ca-central-1 \
  --name eks-iac-pipeline
```

### 5. Verify the cluster

```bash
# All nodes should show STATUS=Ready
kubectl get nodes

# Check the cluster info
kubectl cluster-info

# View outputs (endpoint, OIDC ARN, subnet IDs, etc.)
terraform output
```

---

## CI/CD Pipeline

Two workflows cover the full lifecycle from code review to production deployment.

### Automatic quality gate — `validate.yaml`

**Triggers:** every `git push` to any branch, and every pull request.

```text
  push  ──────────────────────────────────────────────────────► branch check
  PR    ──────────────────────────────────────────────────────► PR check + comment

  Step 1   terraform init       Connects to S3 backend, downloads providers
  Step 2   terraform fmt -check Fails if any file is not canonical format
  Step 3   terraform validate   Type-checks config; no AWS calls made
  Step 4   terraform plan       Full plan against real AWS state
  Step 5   Post PR comment      (PR events only) Pastes plan output into PR thread
```

The plan step uses `continue-on-error: true` so the PR comment always posts, even when the plan itself fails. A final `exit 1` step then marks the job red. This ensures reviewers always see the plan output regardless of whether it succeeded.

**No apply ever happens from this workflow.**

### Manual apply / destroy — `terraform.yml`

**Trigger:** manually from **Actions → EKS-Creation-Using-Terraform → Run workflow**.

Inputs:

| Input | Options | Default |
| --- | --- | --- |
| `tfvars_file` | any path | `dev.tfvars` |
| `action` | `plan` `apply` `destroy` | `apply` |

This workflow is the only path to running `apply` or `destroy` from CI. It uses a `production` GitHub environment, meaning any protection rules you configure (required reviewers, deployment branch policies) must be satisfied before the workflow proceeds.

### Required GitHub secrets

Add these under **Repository Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Description |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | Access key ID for the CI IAM user |
| `AWS_SECRET_ACCESS_KEY` | Secret access key for the CI IAM user |

The CI IAM user needs the following minimum permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
        "s3:ListBucket", "s3:HeadObject"
      ],
      "Resource": [
        "arn:aws:s3:::eks-iac-tf-state",
        "arn:aws:s3:::eks-iac-tf-state/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem", "dynamodb:PutItem",
        "dynamodb:DeleteItem", "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:ca-central-1:*:table/terraform-state-lock"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*", "eks:Describe*", "eks:List*",
        "iam:Get*", "iam:List*"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Environment Separation

Infrastructure values are passed through `.tfvars` files — one per environment. The Terraform code itself is environment-agnostic.

### Current environments

| File | Environment | Region | Notes |
| --- | --- | --- | --- |
| `dev.tfvars` | dev | ca-central-1 | Single NAT Gateway, t3.medium nodes |

### Adding a production environment

1. Create `prod.tfvars` at the repo root (it is gitignored by default — keep it that way for prod since it may contain sensitive values, or store it as a GitHub secret):

```hcl
env          = "prod"
aws_region   = "ca-central-1"
project_name = "eks-iac-pipeline"

tf_state_bucket     = "eks-iac-tf-state"
tf_state_lock_table = "terraform-state-lock"

aws_subnet-1          = "ca-central-1a"
aws_subnet-2          = "ca-central-1b"
public_subnet_cidr_1  = "10.1.1.0/24"
public_subnet_cidr_2  = "10.1.2.0/24"
private_subnet_cidr_1 = "10.1.10.0/24"
private_subnet_cidr_2 = "10.1.11.0/24"

enable_nat_gateway      = true
map_public_ip_on_launch = false
```

1. Update `backend.tf` to use a separate state key for production (or a separate bucket):

```hcl
backend "s3" {
  key = "eks/prod/terraform.tfstate"   # separate key per environment
}
```

1. Trigger the manual workflow with `tfvars_file = prod.tfvars`.

### What changes between environments

| Setting | dev | prod (recommended) |
| --- | --- | --- |
| Node instance type | t3.medium | m5.large or larger |
| Node min/max | 1 / 3 | 2 / 10 |
| NAT Gateways | 1 (single AZ) | 1 per AZ (HA) |
| Cluster logs | api, audit, authenticator | all five log types |
| State key | `eks/terraform.tfstate` | `eks/prod/terraform.tfstate` |
| GitHub environment | — | `production` with required reviewers |

---

## Destroying Infrastructure

> **Warning:** `terraform destroy` is irreversible. All cluster workloads, persistent volumes, and load balancers will be deleted. Ensure you have no data you need to preserve before proceeding.

### Via GitHub Actions (recommended)

1. Go to **Actions → EKS-Creation-Using-Terraform → Run workflow**
2. Set `action` to `destroy` and `tfvars_file` to the environment you want to tear down
3. Confirm the workflow completes successfully

### Locally

```bash
# Preview what will be deleted
terraform plan -destroy -var-file=dev.tfvars

# Destroy (requires typing 'yes' to confirm)
terraform destroy -var-file=dev.tfvars
```

After destroy, the S3 state file and DynamoDB lock table are left in place intentionally — they are cheap to keep and allow you to re-provision from scratch without re-running the one-time setup.

---

## Design Decisions

**Private nodes, public NAT** — worker nodes have no public IP. All outbound traffic routes through a NAT Gateway in the public subnet. This is the standard AWS production pattern: nodes are unreachable from the internet, but can reach ECR, the EKS control plane, and AWS APIs.

**Managed node group** — AWS handles AMI selection, node patching, and graceful cordon/drain during updates. The `desired_size` is excluded from Terraform's lifecycle so the Cluster Autoscaler can manage node count without Terraform fighting it on every plan.

**OIDC provider at creation time** — the OIDC identity provider is provisioned alongside the cluster. Without it, Kubernetes workloads cannot assume IAM roles (IRSA), which blocks the AWS Load Balancer Controller, Cluster Autoscaler, external-dns, and Secrets Manager integration.

**`for_each` over `count` for subnets** — subnets are keyed by AZ name rather than index. Adding or removing an AZ only affects that one subnet in state — `count` would re-number everything after it, causing unnecessary replacements.

**Kubernetes subnet tags** — both subnet tiers are tagged with `kubernetes.io/cluster/<name>` and either `kubernetes.io/role/elb` or `kubernetes.io/role/internal-elb`. These tags are required by the AWS Load Balancer Controller to discover where to place ALBs and NLBs.

**Remote state with locking** — S3 + DynamoDB prevents two concurrent applies from corrupting state. The state file is encrypted at rest. This setup is a prerequisite for any team or CI-based workflow.

---

## Cost Estimate

Running the full dev stack for one hour in `ca-central-1`:

| Resource | Rate | 1 hour |
| --- | --- | --- |
| EKS control plane | $0.10 / hr | $0.10 |
| 2x EC2 t3.medium (ON_DEMAND) | $0.0464 / hr each | $0.09 |
| NAT Gateway | $0.059 / hr + $0.059 / GB | ~$0.09 |
| EBS gp2 — 20 GiB x2 nodes | $0.114 / GB-month | $0.01 |
| CloudWatch Logs (api, audit) | $0.57 / GB ingested | < $0.01 |
| **Total** | | **~$0.29 USD** |

The cluster takes ~15–20 minutes to provision, so your usable window within a 1-hour session is approximately 40 minutes. Tear it down promptly to avoid billing into a second hour.

---

## Roadmap

- [ ] VPC endpoints for ECR, S3, and EKS — eliminate NAT Gateway cost and reduce blast radius
- [ ] KMS envelope encryption for Kubernetes Secrets
- [ ] Per-AZ NAT Gateways for production high availability
- [ ] AWS Load Balancer Controller deployment via Helm
- [ ] Cluster Autoscaler deployment via Helm
- [ ] Restrict `cluster_endpoint_public_access_cidrs` to known office/VPN CIDRs
- [ ] Add tflint and checkov to the CI pipeline for policy-as-code enforcement
- [ ] OIDC-based GitHub Actions authentication (eliminate long-lived IAM credentials)
