from fastapi import HTTPException
from pynamodb.exceptions import DoesNotExist
from .models import UserProfile

def get_user_profile(user_id: str):
    """指定された user_id のプロフィールを取得する。

    DynamoDB からプロフィールを検索する。
    レコードが存在しない場合は None を返す。

    Args:
        user_id (str): 取得対象のユーザーID（Cognito の sub と一致）

    Returns:
        dict | None: プロフィール情報の辞書。存在しない場合は None

    Raises:
        HTTPException: データベースアクセスに失敗した場合 (HTTP 500)
    """
    try:
        profile = UserProfile.get(user_id)
        return {
            "user_id": profile.user_id,
            "nickname": profile.nickname,
            "bio": profile.bio,
            "created_at": profile.created_at,
            "updated_at": profile.updated_at,
            "initialized_by": profile.initialized_by
        }
    except DoesNotExist:
        return None
    except Exception as e:
        print(f"Error fetching profile for {user_id}: {e}")
        raise HTTPException(status_code=500, detail="Database Error")

def put_user_profile(user_id: str, data: dict):
    """指定された user_id のプロフィールを作成/完全上書きする。

    DynamoDB にプロフィール情報を保存する。既存のレコードがあれば上書きされる。

    Args:
        user_id (str): 更新対象のユーザーID
        data (dict): 保存するプロフィール情報の辞書

    Returns:
        dict: 保存されたプロフィール情報の辞書

    Raises:
        HTTPException: データベースアクセスに失敗した場合 (HTTP 500)
    """
    try:
        profile = UserProfile(user_id)
        profile.nickname = data.get("nickname")
        profile.bio = data.get("bio")
        profile.created_at = data.get("created_at")
        profile.updated_at = data.get("updated_at")
        profile.initialized_by = data.get("initialized_by")
        
        profile.save()
        
        return {
            "user_id": user_id,
            **data
        }
    except Exception as e:
        print(f"Error putting profile for {user_id}: {e}")
        raise HTTPException(status_code=500, detail="Database Error")
