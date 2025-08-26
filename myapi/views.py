from rest_framework import viewsets
from .models import Item
from .serializers import ItemSerializer
from django_filters.rest_framework import DjangoFilterBackend

class ItemViewSet(viewsets.ModelViewSet):
    queryset = Item.objects.all()
    serializer_class = ItemSerializer
    filterset_fields = ['product']
    # Enables REST API endpoints to GET, UPDATE, and DELETE items by product name
    filter_backends = [DjangoFilterBackend]
    # Set the filter backend to enable query parameter filtering
    
