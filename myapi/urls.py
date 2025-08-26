from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import ItemViewSet

router = DefaultRouter()
# DefaultRouter(): Creates URLs related to CRUD automatically
router.register(r'items', ItemViewSet)

urlpatterns = [  
    path('', include(router.urls)),
]
