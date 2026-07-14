"""
认证相关的API端点

公共路由（无需登录）：
  - POST /register  用户注册
  - POST /token     获取访问令牌

受保护路由（需要 Bearer Token）：
  - GET  /me        获取当前用户信息
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import timedelta
from pydantic import BaseModel

from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.schemas.auth import Token, UserCreate, UserResponse
from app.services.auth_service import AuthService

# 创建路由器
router = APIRouter()


# 创建登录请求模型（代替 OAuth2PasswordRequestForm）
class LoginRequest(BaseModel):
    username: str
    password: str


# ───────────── 公共路由（无需登录） ─────────────

@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(user_data: UserCreate, db: Session = Depends(get_db)):
    """用户注册"""
    auth_service = AuthService(db)

    # 检查用户是否已存在
    if auth_service.get_user_by_username(user_data.username):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username already registered"
        )

    if auth_service.get_user_by_email(user_data.email):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )

    # 创建用户
    user = auth_service.create_user(user_data)
    return user


@router.post("/token", response_model=Token)
async def login_for_access_token(
    login_data: LoginRequest,
    db: Session = Depends(get_db)
):
    """获取访问令牌（使用JSON而不是表单）"""
    auth_service = AuthService(db)

    # 验证用户
    user = auth_service.authenticate_user(login_data.username, login_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 创建访问令牌
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth_service.create_access_token(
        data={"sub": user["username"]},
        expires_delta=access_token_expires
    )

    return {"access_token": access_token, "token_type": "bearer"}


# ───────────── 受保护路由（需要 Bearer Token） ─────────────

@router.get("/me", response_model=UserResponse)
async def read_users_me(
    current_user: dict = Depends(get_current_user),
):
    """获取当前用户信息"""
    return current_user