"""
Cognito Post-Confirmation Trigger Hook

[NOTE: 本プロジェクトにおける技術的制約と動作仕様について]
本プロジェクトの Cognito User Pool は Terraform で `allow_admin_create_user_only = true` と設定されており、
全ユーザーが管理者 (Admin) によって作成される「招待制」の設計となっている。

AWS Cognito の仕様として、`AdminCreateUser` や `AdminSetUserPassword` などの
管理者向け API 経由でユーザーのステータスが CONFIRMED に遷移した場合、
この `PostConfirmation` トリガーは **一切発火しない**。
(※ 本トリガーはセルフサービスサインアップのフローでのみ発火する)

したがって、本プロジェクトの現在の設定においては、この Lambda スクリプトが
本番運用で自動実行されることはない。
ただし、「セルフサービスサインアップ機能が有効化された場合への備え」および
「Terraform による ZIP デプロイ方式のリファレンス実装（技術検証用）」として
あえてこのコードとインフラ定義を残している。

実際の初期化ロジックは API 側の遅延初期化 (Lazy Initialization) に倒している。
"""

import os
import boto3
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('DYNAMODB_TABLE_NAME')
table = dynamodb.Table(table_name)

def handler(event, context):
    """
    Cognito の PostConfirmation 時に発火する Lambda ハンドラ。
    新規ユーザーの初期プロフィールを DynamoDB に自動登録する。
    """
    print("Received event:", event)
    
    # イベントが PostConfirmation かどうか念のため確認
    if event.get('triggerSource') != 'PostConfirmation_ConfirmSignUp':
        return event

    user_attributes = event.get('request', {}).get('userAttributes', {})
    
    # Cognito の sub をシステム内のユーザーIDとして利用
    user_id = user_attributes.get('sub')
    if not user_id:
        print("Error: No sub found in user attributes")
        return event

    # preferred_username があればそれを利用し、なければ通常の username を利用
    username = event.get('userName', 'Unknown')
    nickname = user_attributes.get('preferred_username', username)

    # 現在時刻 (UTC)
    now_iso = datetime.now(timezone.utc).isoformat()

    try:
        table.put_item(
            Item={
                'user_id': user_id,
                'nickname': nickname,
                'bio': 'Nice to meet you!',
                'created_at': now_iso,
                'updated_at': now_iso,
                'initialized_by': 'cognito_trigger'
            }
        )
        print(f"Successfully created profile for user: {user_id}")
    except Exception as e:
        print(f"Error saving to DynamoDB: {e}")
        # 例外が発生しても、Cognito側のサインアップ処理をブロックしないようにする
        # (ここで失敗しても、API側の遅延初期化でカバーされるハイブリッド構成)

    # 必須: 受け取ったイベントをそのまま返す
    return event
