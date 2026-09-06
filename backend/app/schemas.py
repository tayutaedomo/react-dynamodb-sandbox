from pydantic import BaseModel


class ProfileUpdate(BaseModel):
    """プロフィール更新リクエストを受け取るための Pydantic スキーマ。

    フロントエンドから送信される JSON ペイロードのバリデーションと型定義を行う。

    Attributes:
        nickname (str): ユーザーの新しい表示名。デフォルトは空文字列。
        bio (str): ユーザーの新しい自己紹介文。デフォルトは空文字列。
    """

    nickname: str = ""
    bio: str = ""
