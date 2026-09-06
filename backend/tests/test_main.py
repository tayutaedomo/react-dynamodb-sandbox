from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock
from pynamodb.exceptions import DoesNotExist

from app.main import app
from app.auth import verify_token

# FastAPI のテスト用クライアントを作成
client = TestClient(app)

def test_health_check():
    """
    /api/health エンドポイントが正常に動作するか（認証不要）のテスト
    """
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "message": "Backend is running"}


def test_get_current_user_success():
    """
    /api/me エンドポイントの成功ケースのテスト
    FastAPI の Dependency Override を利用して、JWT の検証ロジックをモック（偽装）します。
    """
    
    # 1. 認証成功時に auth.py の verify_token が返すはずのデータのモック（ダミー）を定義
    mock_claims = {
        "sub": "12345678-abcd-1234-abcd-1234567890ab",
        "cognito:username": "testuser1",
        "username": "testuser1"
    }

    # 2. テスト実行中のみ、verify_token の処理を上記のモックデータを返す関数にすり替える
    app.dependency_overrides[verify_token] = lambda: mock_claims

    # 3. テストクライアントを使ってエンドポイントに GET リクエストを送信
    # ※ override しているため、トークン自体は適当な文字列で問題ありません
    headers = {"Authorization": "Bearer dummy_token"}
    response = client.get("/api/me", headers=headers)

    # 4. 結果の検証 (アサーション)
    assert response.status_code == 200
    data = response.json()
    assert data["user_id"] == "12345678-abcd-1234-abcd-1234567890ab"
    assert data["username"] == "testuser1"
    
    # 5. 他のテストに影響を与えないよう、モックを解除する
    app.dependency_overrides.clear()

# --- DynamoDB (Profile) 関連のテスト ---

@patch("app.crud.UserProfile.get")
def test_read_profile_existing_user(mock_get):
    """正常系: 既にプロフィールが存在するユーザーの GET リクエスト"""
    
    mock_claims = {
        "sub": "test-user-id-123",
        "username": "testuser"
    }
    app.dependency_overrides[verify_token] = lambda: mock_claims
    
    mock_profile = MagicMock()
    mock_profile.user_id = "test-user-id-123"
    mock_profile.nickname = "Existing Nickname"
    mock_profile.bio = "Existing Bio"
    mock_profile.created_at = "2026-01-01T00:00:00"
    mock_profile.updated_at = "2026-01-01T00:00:00"
    mock_profile.initialized_by = "api_lazy_init"
    mock_get.return_value = mock_profile

    response = client.get("/api/me/profile", headers={"Authorization": "Bearer dummy"})
    
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["profile"]["nickname"] == "Existing Nickname"
    assert data["profile"]["user_id"] == "test-user-id-123"
    mock_get.assert_called_once_with("test-user-id-123")
    
    app.dependency_overrides.clear()


@patch("app.crud.UserProfile.save")
@patch("app.crud.UserProfile.get")
def test_read_profile_lazy_init(mock_get, mock_save):
    """正常系: プロフィールが存在しないユーザーの GET リクエスト (遅延初期化)"""
    
    mock_claims = {
        "sub": "test-user-id-123",
        "username": "testuser"
    }
    app.dependency_overrides[verify_token] = lambda: mock_claims
    
    mock_get.side_effect = DoesNotExist()
    mock_save.return_value = None

    response = client.get("/api/me/profile", headers={"Authorization": "Bearer dummy"})
    
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["profile"]["user_id"] == "test-user-id-123"
    assert data["profile"]["nickname"] == "testuser"
    assert data["profile"]["initialized_by"] == "api_lazy_init"
    mock_get.assert_called_once_with("test-user-id-123")
    assert mock_save.called
    
    app.dependency_overrides.clear()


@patch("app.crud.UserProfile.save")
@patch("app.crud.UserProfile.get")
def test_update_profile(mock_get, mock_save):
    """正常系: プロフィールの POST リクエスト (更新)"""
    
    mock_claims = {
        "sub": "test-user-id-123",
        "username": "testuser"
    }
    app.dependency_overrides[verify_token] = lambda: mock_claims
    
    mock_profile = MagicMock()
    mock_profile.user_id = "test-user-id-123"
    mock_profile.nickname = "Old Nickname"
    mock_profile.bio = "Old Bio"
    mock_get.return_value = mock_profile
    
    payload = {
        "nickname": "New Nickname",
        "bio": "New Bio"
    }
    response = client.post("/api/me/profile", json=payload, headers={"Authorization": "Bearer dummy"})
    
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["profile"]["nickname"] == "New Nickname"
    assert data["profile"]["bio"] == "New Bio"
    assert mock_save.called
    
    app.dependency_overrides.clear()
