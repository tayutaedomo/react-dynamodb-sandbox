from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from .auth import verify_token

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
    return {"status": "ok", "message": "Backend is running"}

@app.get("/api/me")
def get_current_user(claims: dict = Depends(verify_token)):
    """
    認証済みユーザーの情報を返すエンドポイント
    """
    user_id = claims.get("sub")
    username = claims.get("username", claims.get("cognito:username"))
    
    return {
        "user_id": user_id,
        "username": username,
        "claims": claims
    }
