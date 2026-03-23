# EKS IaC Pipeline

> Automated provisioning of a production-ready Amazon EKS cluster on AWS using Terraform — from VPC to running nodes in a single `terraform apply`.

## Overview

This project provisions a fully functional Kubernetes cluster on AWS using modular, reusable Terraform. It is designed to reflect the kind of infrastructure automation used in real production environments — remote state, least-privilege IAM, private node networking, and a CI pipeline that validates every change before it lands.

**What gets built:**

- A custom VPC with public and private subnets across two availability zones
- A NAT Gateway so private nodes can reach the internet without being exposed
- An EKS control plane with a managed node group running in the private subnets
- All required IAM roles, policies, and an OIDC provider for workload identity (IRSA)
- Security groups with minimal, explicit ingress/egress rules
- Remote Terraform state in S3 with DynamoDB locking
- A GitHub Actions CI pipeline that runs `fmt → validate → plan` on every push and PR

---

## Architecture

<!-- ------------------------------------------------------------------ -->
<!-- ARCHITECTURE DIAGRAM                                                  -->
<!-- Replace this comment block with your diagram image once created.     -->
<!--                                                                      -->
<!-- Recommended tools:                                                    -->
<!--   - draw.io (diagrams.net) — free, exports PNG/SVG                  -->
<!--   - Lucidchart                                                        -->
<!--   - AWS Architecture Icons (official icon set)                       -->
<!--                                                                      -->
<!-- Suggested diagram elements:                                           -->
<!--   GitHub -> GitHub Actions -> S3 (Terraform state)                  -->
<!--   VPC                                                                 -->
<!--     +-- Public Subnet AZ-a  ->  NAT Gateway                         -->
<!--     +-- Public Subnet AZ-b                                            -->
<!--     +-- Private Subnet AZ-a  ->  Worker Node (t3.medium)            -->
<!--     +-- Private Subnet AZ-b  ->  Worker Node (t3.medium)            -->
<!--   EKS Control Plane (managed by AWS)                                 -->
<!--   IAM Roles (cluster role, node role, OIDC provider)                 -->
<!-- ------------------------------------------------------------------ -->

```text
[ Architecture diagram coming soon ]
```

> **Note:** Save your diagram as `docs/architecture.png` and replace the placeholder above with:
> `![Architecture](docs/architecture.png)`

---

## Stack

| Layer | Technology |
| --- | --- |
| Infrastructure as Code | Terraform >= 1.14.7 |
| Cloud provider | AWS (ca-central-1) |
| Container orchestration | Amazon EKS 1.30 |
| Networking | Custom VPC, public/private subnets, NAT Gateway |
| Node compute | EC2 t3.medium (managed node group) |
| State management | S3 + DynamoDB state lock |
| CI/CD | GitHub Actions |
| Workload identity | OIDC provider (IRSA-ready) |

---

## Project Structure

```text
eks-iac-pipeline/
├── main.tf                   # Root module — wires VPC and EKS together
├── variables.tf              # Input variable declarations
├── outputs.tf                # Root-level outputs (endpoint, IDs, OIDC ARN)
├── provider.tf               # AWS + TLS provider config
├── backend.tf                # S3 remote state + DynamoDB lock
├── dev.tfvars                # Dev environment variable values
│
├── modules/
│   ├── vpc/                  # Reusable VPC module
│   │   ├── main.tf           # VPC, subnets, IGW, NAT, route tables
│   │   ├── variable.tf
│   │   └── output.tf
│   │
│   └── eks/                  # Reusable EKS module
│       ├── main.tf           # Cluster, node group, IAM, SGs, OIDC
│       ├── variable.tf
│       └── output.tf
│
└── .github/
    └── workflows/
        ├── validate.yaml     # CI: fmt + validate + plan on push/PR
        └── terraform.yml     # Manual: plan / apply / destroy
```

---

## How It Works

### 1. VPC Module

A dedicated VPC (`10.0.0.0/16`) is created with two public and two private subnets spread across two availability zones. The public subnets host the NAT Gateway; all worker nodes run in the private subnets and reach the internet through it. Route tables and subnet tags (`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`) are applied so the AWS Load Balancer Controller can discover subnets automatically.

### 2. EKS Module

The EKS control plane is placed inside the VPC using private subnets. Two security groups are created with explicit rules:

- **Cluster SG** — accepts port 443 from nodes, allows all egress
- **Node SG** — node-to-node unrestricted, accepts port 10250 and ephemeral ports from the control plane

A managed node group runs `t3.medium` instances (`ON_DEMAND`) with autoscaling configured between 1 and 3 nodes. IAM roles are created for both the control plane and worker nodes with the minimum required AWS managed policies. An OIDC provider is registered so that Kubernetes service accounts can assume IAM roles (IRSA) — a requirement for add-ons like the AWS Load Balancer Controller, Cluster Autoscaler, and external-dns.

### 3. State Management

Terraform state is stored remotely in an S3 bucket (`eks-iac-tf-state`) with server-side encryption enabled. A DynamoDB table (`terraform-state-lock`) prevents concurrent apply operations from corrupting state.

### 4. CI Pipeline

Every commit to any branch and every pull request triggers the `validate.yaml` workflow:

```text
push / pull_request
       |
       v
terraform init       <- connects to S3 backend
       |
terraform fmt -check <- fails if formatting is off
       |
terraform validate   <- type-checks config (no AWS calls)
       |
terraform plan       <- full plan against real AWS state
       |
       v (on PR only)
Post plan as PR comment
```

On PRs, the full plan output is posted as a comment so reviewers can see exactly what will change before merging.

The `terraform.yml` workflow is triggered manually from the GitHub Actions UI and is the only way to run `apply` or `destroy` from CI. It uses a `production` environment so GitHub's protection rules apply before any destructive operation runs.

---

## Prerequisites

| Tool | Version |
| --- | --- |
| Terraform | >= 1.14.7 |
| AWS CLI | >= 2.x |
| kubectl | >= 1.30 |

You will also need:

- An AWS account with permissions to create VPC, EKS, IAM, and S3 resources
- An S3 bucket named `eks-iac-tf-state` in `ca-central-1`
- A DynamoDB table named `terraform-state-lock` with partition key `LockID` (String)

---

## Deployment

### Local deployment

```bash
# 1. Clone the repository
git clone https://github.com/<your-username>/eks-iac-pipeline.git
cd eks-iac-pipeline

# 2. Configure AWS credentials
aws configure

# 3. Initialize Terraform (connects to S3 backend)
terraform init

# 4. Preview what will be created
terraform plan -var-file=dev.tfvars

# 5. Apply
terraform apply -var-file=dev.tfvars

# 6. Configure kubectl
aws eks update-kubeconfig --region ca-central-1 --name eks-iac-pipeline

# 7. Verify nodes are ready
kubectl get nodes
```

### CI deployment (GitHub Actions)

1. Fork or push the repository to GitHub.
2. Add two repository secrets under **Settings → Secrets and variables → Actions**:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
3. Every push will automatically run the quality gate (`fmt → validate → plan`).
4. To apply, go to **Actions → EKS-Creation-Using-Terraform → Run workflow** and select `apply`.

### Teardown

```bash
# Local
terraform destroy -var-file=dev.tfvars

# Or via GitHub Actions -> Run workflow -> select 'destroy'
```

---

## Key Design Decisions

**Private nodes, public NAT** — worker nodes have no public IP. All outbound traffic (ECR image pulls, AWS API calls) routes through a NAT Gateway in the public subnet. This is the standard production pattern for EKS.

**Managed node group over self-managed** — AWS handles node patching, AMI updates, and graceful draining. The `desired_size` is ignored by Terraform after initial creation so the Cluster Autoscaler can manage node count freely.

**OIDC provider included** — the OIDC provider is provisioned alongside the cluster so IRSA is available immediately. This is a prerequisite for any AWS-integrated Kubernetes add-on.

**`for_each` over `count` in modules** — subnets are keyed by availability zone name, not by index. This means adding or removing an AZ only affects that subnet's resource, not every subsequent one.

**Remote state with locking** — S3 + DynamoDB prevents two engineers (or two CI runs) from applying simultaneously and corrupting state.

---

## Estimated Cost (dev environment, 1 hour)

| Resource | Cost |
| --- | --- |
| EKS control plane | $0.10 |
| 2x t3.medium nodes | $0.09 |
| NAT Gateway + data | $0.09 |
| EBS volumes (40 GiB) | $0.01 |
| **Total** | **~$0.29 USD** |

---

## Future Improvements

- [ ] Add VPC endpoints for ECR, S3, and EKS to eliminate NAT Gateway cost in production
- [ ] Enable KMS envelope encryption for Kubernetes secrets
- [ ] Add per-AZ NAT Gateways for high availability
- [ ] Deploy the AWS Load Balancer Controller as a Helm release
- [ ] Add the Cluster Autoscaler
- [ ] Restrict `cluster_endpoint_public_access_cidrs` to known CIDRs
- [ ] Add tflint and checkov to the CI pipeline for deeper static analysis

---

