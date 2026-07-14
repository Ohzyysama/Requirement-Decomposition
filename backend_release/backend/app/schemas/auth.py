"""
认证相关的模式
"""
from typing import Optional
from pydantic import BaseModel, EmailStr


class Token(BaseModel):
    """令牌响应"""
    access_token: str
    token_type: str


class TokenData(BaseModel):
    """令牌数据"""
    username: Optional[str] = None


class UserBase(BaseModel):
    """用户基础"""
    username: str
    email: EmailStr
    full_name: Optional[str] = None


class UserCreate(UserBase):
    """用户创建"""
    password: str


class UserUpdate(BaseModel):
    """用户更新"""
    email: Optional[EmailStr] = None
    full_name: Optional[str] = None
    password: Optional[str] = None


class UserInDB(UserBase):
    """数据库中的用户"""
    id: str
    is_active: bool = True
    is_superuser: bool = False

    class Config:
        from_attributes = True


class UserResponse(UserInDB):
    """用户响应"""
    pass