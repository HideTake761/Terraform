The infrastructure of [HideTake761/CI-CD-Django-REST-API-with-Docker-on-AWS-ECS-Fargate](https://github.com/HideTake761/CI-CD-Django-REST-API-with-Docker-on-AWS-ECS-Fargate).

Environment:
- Host OS: Windows 11 Home 25H2  
- Visual Studio Code  1.108.2  
- Terraform v1.13.4  
- AWS CLI 2.30.6  
  
AWS:  
- Compute : ECS(Fargate)  
- Container Management : ECR
- Database : RDS PostgreSQL
- Networking : ALB(Application Load Balancer), VPC, VPC Endpoint  
  VPC Endpoints were chosen instead of a NAT Gateway to avoid unnecessary internet traffic. 
- Monitoring & Logging : CloudWatch Logs, Alarm
- IaC : Terraform  
- Cost Management : AWS Budgets  
- System Architecture Diagram is below  
  <img src="./AWS ECS RDS.jpg" alt="System Architecture Diagram" width="600" />  
  
Terraform files:  
- providers.tf : Terraform Version Requirement, AWS Region and Profile  
- network.tf : Network Infrastructure (VPC, Subnets, Route Tables, VPC Endpoints)
- alb.tf : ALB, Listener, Target Group and Security Group
- rds.tf : PostgreSQL Database, Password Generation and Secrets Manager Registration  
- ecs.tf : ECS Cluster, Task Definition and Security Group
- monitoring.tf : CloudWatch Logs, Alarms and Budgets
