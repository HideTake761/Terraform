from django.db import models
from django.core.validators import MinValueValidator

class Item(models.Model):

    product = models.CharField(max_length=20)
    price = models.IntegerField(validators=[MinValueValidator(0)])
    
    def __str__(self):
    
        return self.product
