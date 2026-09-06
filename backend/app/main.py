from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
import datetime

from .auth import verify_token
from .crud import get_user_profile, put_user_profile
from .schemas import ProfileUpdate

app = FastAPI(title="React DynamoDB Sandbox API")

# Vite のデフォルトポート (5173) からのアクセスを許可
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/api/health")
def health_check():
    """ヘルスチェック用エンドポイント。

    バックエンドが正常に起動しているかを確認するためのエンドポイント。

    Returns:
        dict: ステータスとメッセージを含む辞書
    """
    return {"status": "ok", "message": "Backend is running"}

@app.get("/api/me")
def get_current_user(claims: dict = Depends(verify_token)):
    """認証済みユーザーの基本情報を取得する。

    Cognito から発行された JWT のクレーム情報を元に、ユーザーの基本情報を返す。

    Args:
        claims (dict): verify_token 依存関係によって注入される検証済みクレーム

    Returns:
        dict: ユーザーID、ユーザー名、クレームの全量を含む辞書
    """
    user_id = claims.get("sub")
    username = claims.get("username", claims.get("cognito:username"))
    
    return {
        "user_id": user_id,
        "username": username,
        "claims": claims
    }

@app.get("/api/me/profile")
def read_profile(claims: dict = Depends(verify_token)):
    """自分のプロフィールを取得する。

    DynamoDB からプロフィールを取得する。
    存在しない場合は、デフォルトデータを作成して返す（遅延初期化）。

    Args:
        claims (dict): verify_token 依存関係によって注入される検証済みクレーム

    Returns:
        dict: ステータスとプロフィール情報を含む辞書
    """
    user_id = claims.get("sub")
    profile = get_user_profile(user_id)
    
    if profile is None:
        # 遅延初期化 (Lazy Initialization)
        username = claims.get("username", claims.get("cognito:username", "Unknown"))
        default_data = {
            "nickname": username,
            "bio": "Nice to meet you!",
            "created_at": datetime.datetime.now(datetime.UTC).isoformat(),
            "initialized_by": "api_lazy_init" # どこで初期化されたかをマーキング
        }
        profile = put_user_profile(user_id, default_data)
        
    return {"status": "success", "profile": profile}

@app.post("/api/me/profile")
def update_profile(data: ProfileUpdate, claims: dict = Depends(verify_token)):
    """自分のプロフィールを更新する。

    DynamoDB のプロフィール情報を更新する。既存の情報は保持され、指定されたフィールドのみ更新される。

    Args:
        data (ProfileUpdate): クライアントから送信されるプロフィール更新データ
        claims (dict): verify_token 依存関係によって注入される検証済みクレーム

    Returns:
        dict: ステータスと更新後のプロフィール情報を含む辞書
    """
    user_id = claims.get("sub")
    
    # 既存のデータを取得（一部更新のため）
    profile = get_user_profile(user_id) or {}
    
    # マージして保存
    updated_data = {
        **profile,
        "nickname": data.nickname,
        "bio": data.bio,
        "updated_at": datetime.datetime.now(datetime.UTC).isoformat()
    }
    
    saved = put_user_profile(user_id, updated_data)
    return {"status": "success", "profile": saved}
