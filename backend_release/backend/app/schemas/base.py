"""
基础模式
"""
from typing import Optional, Generic, TypeVar
from pydantic import BaseModel as PydanticBaseModel
from pydantic.generics import GenericModel
from datetime import datetime

DataT = TypeVar("DataT")


class BaseModel(PydanticBaseModel):
    """基础模型"""
    class Config:
        from_attributes = True  # 替代原来的 orm_mode
        populate_by_name = True
        use_enum_values = True


class BaseResponse(BaseModel):
    """基础响应"""
    success: bool = True
    message: Optional[str] = None


class PaginatedResponse(GenericModel, Generic[DataT]):
    """分页响应"""
    items: list[DataT]
    total: int
    page: int
    size: int
    pages: int


class TimestampMixin(BaseModel):
    """时间戳混合"""
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class IDMixin(BaseModel):
    """ID混合"""
    id: str