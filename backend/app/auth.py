import os
import json
import httpx
import jwt
from jwt.algorithms import RSAAlgorithm
from fastapi import HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

COGNITO_REGION = os.environ.get("COGNITO_REGION", "ap-northeast-1")
COGNITO_USER_POOL_ID = os.environ.get("COGNITO_USER_POOL_ID", "")
COGNITO_CLIENT_ID = os.environ.get("COGNITO_CLIENT_ID", "")

JWKS_URL = f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com/{COGNITO_USER_POOL_ID}/.well-known/jwks.json"
ISSUER = f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com/{COGNITO_USER_POOL_ID}"

security = HTTPBearer()

jwks_cache = {}

def get_jwks():
    global jwks_cache
    if not jwks_cache:
        try:
            response = httpx.get(JWKS_URL)
            response.raise_for_status()
            jwks_cache = response.json()
        except httpx.HTTPError as e:
            print(f"Error fetching JWKS: {e}")
            raise HTTPException(status_code=500, detail="Could not fetch JWKS")
    return jwks_cache

def verify_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    token = credentials.credentials
    try:
        # ヘッダーから kid を取得
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get("kid")
        if not kid:
            raise HTTPException(status_code=401, detail="Invalid token header: missing kid")

        # JWKS から一致する公開鍵を取得
        jwks = get_jwks()
        key_data = next((key for key in jwks.get("keys", []) if key["kid"] == kid), None)
        if not key_data:
            raise HTTPException(status_code=401, detail="Public key not found in JWKS")

        # 公開鍵オブジェクトを生成
        public_key = RSAAlgorithm.from_jwk(json.dumps(key_data))

        # token_use (access か id か) を判別するために一度未検証でデコード
        unverified_claims = jwt.decode(token, options={"verify_signature": False})
        token_use = unverified_claims.get("token_use")
        
        if token_use == "access":
            # Access トークンの検証
            claims = jwt.decode(
                token,
                public_key,
                algorithms=["RS256"],
                issuer=ISSUER,
                options={"verify_aud": False}
            )
            if claims.get("client_id") != COGNITO_CLIENT_ID:
                raise HTTPException(status_code=401, detail="Invalid client_id in access token")
        elif token_use == "id":
            # ID トークンの検証
            claims = jwt.decode(
                token,
                public_key,
                algorithms=["RS256"],
                audience=COGNITO_CLIENT_ID,
                issuer=ISSUER
            )
        else:
            raise HTTPException(status_code=401, detail="Invalid token_use")

        return claims

    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except jwt.InvalidTokenError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}")
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Authentication error: {e}")
