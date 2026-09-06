import unittest
from unittest.mock import patch, MagicMock
import os
import json

# テスト実行時に環境変数をセット
os.environ['DYNAMODB_TABLE_NAME'] = 'test-table'

# boto3.resource が呼ばれる前にモック化するために、import 前に patch するか、
# モジュールインポート時に発火する部分をパッチで囲みます。
with patch('boto3.resource') as mock_resource:
    mock_table = MagicMock()
    mock_dynamodb = MagicMock()
    mock_dynamodb.Table.return_value = mock_table
    mock_resource.return_value = mock_dynamodb
    
    # ここで main.py をインポート
    import main

class TestCognitoHook(unittest.TestCase):
    def setUp(self):
        # 毎テスト実行前に呼び出し履歴をリセット
        mock_table.put_item.reset_mock()
        self.mock_table = mock_table

    def test_post_confirmation_success(self):
        """正常系: Cognito の PostConfirmation イベントで DynamoDB に書き込まれること"""
        event = {
            "triggerSource": "PostConfirmation_ConfirmSignUp",
            "userName": "testuser_cognito",
            "request": {
                "userAttributes": {
                    "sub": "user-uuid-1234",
                    "preferred_username": "nickname123"
                }
            }
        }
        
        result = main.handler(event, None)
        
        # 入力イベントがそのまま返されること
        self.assertEqual(result, event)
        
        # DynamoDB に put_item が1回呼ばれたこと
        self.mock_table.put_item.assert_called_once()
        
        # 呼ばれた引数の中身を検証
        call_args = self.mock_table.put_item.call_args[1]['Item']
        self.assertEqual(call_args['user_id'], 'user-uuid-1234')
        self.assertEqual(call_args['nickname'], 'nickname123')
        self.assertEqual(call_args['initialized_by'], 'cognito_trigger')

    def test_missing_sub(self):
        """異常系: sub が存在しない場合は書き込みを行わずに終了すること"""
        event = {
            "triggerSource": "PostConfirmation_ConfirmSignUp",
            "userName": "testuser",
            "request": {
                "userAttributes": {} # subなし
            }
        }
        result = main.handler(event, None)
        self.assertEqual(result, event)
        self.mock_table.put_item.assert_not_called()
        
    def test_wrong_trigger_source(self):
        """正常系: 別のトリガーソースのイベントは無視すること"""
        event = {
            "triggerSource": "PreSignUp_AdminCreateUser",
            "userName": "testuser"
        }
        result = main.handler(event, None)
        self.assertEqual(result, event)
        self.mock_table.put_item.assert_not_called()

if __name__ == '__main__':
    unittest.main()
