from fastapi.testclient import TestClient
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
