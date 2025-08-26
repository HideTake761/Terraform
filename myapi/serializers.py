from rest_framework import serializers
from .models import Item

class ItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = Item
        fields = ['id', 'product', 'price']
    
    def validate_product(self, value):
        if not value.strip():
            raise serializers.ValidationError("Product name cannot be empty.")
        return value
