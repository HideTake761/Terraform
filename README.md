Environment:
- Host OS: Windows 11 Home 24H2  
- Visual Studio Code  
- Docker Desktop for Windows  
- Docker Image: Python:3.13-slim linux/amd64  
- Docker: version 28.3.2  
- Python 3.9.16  
- Django 5.2.5, Django REST Framework 3.16.1, Django-filter 25.1  
- SQLite, sqlparse 0.5.3  

API server Functions:
- Records and stores product names(product) and prices(price)
- No authentication
- Searchable by product name
- No pagination

Setting Up Volume Mounts from Windows 11 to a Docker Container(in Windows PC):

>docker run -it -p 8000:8000 -v C:\Users\HideTake761\Django\api_server:/app --name api_server python:3.13-slim bash
<br>
Unit Test: 
https://github.com/HideTake761/CICD-Django-REST-Framework/blob/main/myapi/tests.py
<br>
<br>
REST API Request Test:<br>
Please see https://github.com/HideTake761/CICD-Django-REST-Framework/blob/main/REST_API_TEST.md
<br>
<br>
  
CI/CD Pipeline (via GitHub Actions):
- Trigger: Push to the main branch
- CI: Runs unit tests automatically
- CD: If tests pass, it builds a Docker image and pushes it to Docker Hub  
https://hub.docker.com/r/hideto861/django-rest-framework

Please see<br>
https://github.com/HideTake761/CICD-Django-REST-Framework/blob/main/.github/workflows/docker-build.yaml 
<br>
for more detail.


