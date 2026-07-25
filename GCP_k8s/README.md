The infrastructure of [HideTake761/Go-audit-Django-API-GKE](https://github.com/HideTake761/Go-audit-Django-API-GKE).

Environment:
- Host OS: Windows 11 Home 25H2  
- Visual Studio Code  1.129.1  
- Terraform v1.13.4  
- gcloud 576.0.0  
  
GCP:  
- Compute: GKE  
- Container Management: Artifact Registry
- Database: Cloud SQL for PostgreSQL
- Networking: External Application Load Balancer, VPC, Cloud NAT, Cloud Router,
  Private Services Access(between GKE and Cloud SQL)
- Security & CI/CD: Workload Identity Federation(for GitHub Actions authentication)
- Monitoring & Logging: Cloud Logging, Cloud Monitoring

The Cloud Storage bucket for Terraform state files was created manually in the GCP console before running 'terraform apply'.

System Architecture Diagram is below  
  <img src="./GCP Kubernetes.jpg" alt="System Architecture Diagram" width="600" />  
