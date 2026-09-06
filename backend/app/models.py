import os
from pynamodb.models import Model
from pynamodb.attributes import UnicodeAttribute

class UserProfile(Model):
    """DynamoDB のプロフィールテーブルに対応する PynamoDB モデル。

    react-dynamodb-sandbox-profiles テーブルとのマッピングを定義する。

    Attributes:
        user_id (UnicodeAttribute): パーティションキー。Cognito の sub (ユーザーID) を格納する。
        nickname (UnicodeAttribute): ユーザーの表示名。
        bio (UnicodeAttribute): ユーザーの自己紹介文。
        created_at (UnicodeAttribute): レコードの作成日時 (ISO 8601 形式)。
        updated_at (UnicodeAttribute): レコードの最終更新日時 (ISO 8601 形式)。
        initialized_by (UnicodeAttribute): レコードを初期化したシステムまたは手段の識別子。
    """
    class Meta:
        table_name = os.environ.get("DYNAMODB_TABLE_NAME", "react-dynamodb-sandbox-profiles")
        region = os.environ.get("AWS_REGION", "ap-northeast-1")
    
    user_id = UnicodeAttribute(hash_key=True)
    nickname = UnicodeAttribute(null=True)
    bio = UnicodeAttribute(null=True)
    created_at = UnicodeAttribute(null=True)
    updated_at = UnicodeAttribute(null=True)
    initialized_by = UnicodeAttribute(null=True)
