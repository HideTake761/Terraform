Purpose & Usage Context:  

This API server records and stores product names(product) and prices(price) as a part of a microservice architecture.  
By developing with Docker and pushing the image to Docker Hub, any team member can verify the application in the same environment.

Environment:
- Host OS: Windows 11 Home 24H2  
- Visual Studio Code  
- Docker Desktop for Windows  
- Docker Image: Python:3.13-slim linux/amd64  
- Docker: version 28.3.2  
- Python 3.9.16  
- Django 5.2.5, Django REST Framework 3.16.1, Django-filter 25.1  
Django REST Framework was chosen based on existing experience with Django, enabling quicker development and easier long-term maintenance compared to adopting a new framework like FastAPI.
- SQLite, sqlparse 0.5.3  
SQLite was selected because it is Django’s default RDBMS and easy to set up. More advanced RDBMSs such as MySQL or PostgreSQL were considered unnecessary due to the limited scale of the data handled in this project.

API server Functions:
- No authentication
- Searchable by product name
- No pagination

Setting Up Volume Mounts from Windows 11 to a Docker Container(in Windows PC):

>docker run -it -p 8000:8000 -v C:\Users\HideTake761\Django\api_server:/app --name api_server python:3.13-slim bash
<br>
Unit Test: 
https://github.com/HideTake761/CICD-Django-REST-Framework/blob/main/myapi/tests.py
  
Current test coverage measured by **coverage.py** is **97%**.
<br>
<br>
REST API Request Test:<br>
Please see https://github.com/HideTake761/CICD-Django-REST-Framework/blob/main/REST_API_TEST.md
<br>
<br>
  
CI/CD Pipeline (via GitHub Actions):  
GitHub Actions was selected due to deep integration with the GitHub ecosystem. It can be configured through the GitHub UI and a YAML file which makes it much simpler to implement than alternatives like Jenkins or CircleCI.
- Trigger: Push to the main branch
- CI: Runs unit tests automatically
- CD: If tests pass, it builds a Docker image and pushes it to Docker Hub  
https://hub.docker.com/r/hideto861/django-rest-framework

   Please see the below for more detail.<br>
   https://github.com/HideTake761/CICD-Django-REST-Framework/blob/main/.github/workflows/docker-build.yaml 



