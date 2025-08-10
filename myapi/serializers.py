from rest_framework import serializers
from .models import Item
# 同じディレクトリにあるmodels.pyファイルからItemモデルをインポート

class ItemSerializer(serializers.ModelSerializer):
    class Meta: # ItemSerializerクラスの設定を行う内部クラスMetaを定義
        model = Item # シリアライザが扱うモデルを指定
        fields = ['id', 'product', 'price']
        # シリアライズされるときに含めるフィールドをproduct、priceに限定
        # fields = '__all__' :シリアライザが対象とするモデル
        # (今回だとItemモデル)に存在するすべてのフィールドを自動的に含める
    
    # (models.pyの)CharField()はデフォルトで blank=Falseなので、フォームでは空欄でエラーになる。
    # APIのバリデーションで明確にエラーを出すための記述
    def validate_product(self, value):
        if not value.strip():
            raise serializers.ValidationError("商品名は空にできません")
        return value
