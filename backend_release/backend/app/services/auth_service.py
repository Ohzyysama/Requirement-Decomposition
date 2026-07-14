"""
认证服务
"""
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from app.core.config import settings
from app.schemas.auth import UserCreate  # 添加这行导入
from app.repositories.user_repo import UserRepository

# 密码哈希上下文
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


class AuthService:
    """认证服务"""

    def __init__(self, db: Session):
        self.db = db
        self.user_repo = UserRepository(db)

    def verify_password(self, plain_password: str, hashed_password: str) -> bool:
        """验证密码"""
        return pwd_context.verify(plain_password, hashed_password)

    def get_password_hash(self, password: str) -> str:
        """获取密码哈希"""
        return pwd_context.hash(password)

    def authenticate_user(self, username: str, password: str) -> Optional[Dict[str, Any]]:
        """验证用户"""
        user = self.get_user_by_username(username)
        if not user:
            return None

        if not self.verify_password(password, user.hashed_password):
            return None

        return user.to_dict()

    def get_user_by_username(self, username: str):
        """通过用户名获取用户"""
        return self.user_repo.get_user_by_username(username)

    def get_user_by_email(self, email: str):
        """通过邮箱获取用户"""
        return self.user_repo.get_user_by_email(email)

    def create_user(self, user_data: UserCreate):  # 现在 UserCreate 已定义
        """创建用户"""
        hashed_password = self.get_password_hash(user_data.password)

        user = self.user_repo.create_user(
            username=user_data.username,
            email=user_data.email,
            hashed_password=hashed_password,
            full_name=user_data.full_name
        )

        return user.to_dict()

    def create_access_token(self, data: dict, expires_delta: Optional[timedelta] = None) -> str:
        """创建访问令牌"""
        to_encode = data.copy()

        if expires_delta:
            expire = datetime.utcnow() + expires_delta
        else:
            expire = datetime.utcnow() + timedelta(minutes=15)

        to_encode.update({"exp": expire})
        encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
        return encoded_jwt

    def get_current_user(self, token: str) -> Optional[Dict[str, Any]]:
        """获取当前用户"""
        try:
            payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
            username: str = payload.get("sub")
            if username is None:
                return None
        except JWTError:
            return None

        user = self.get_user_by_username(username)
        if user is None:
            return None

        return user.to_dict()