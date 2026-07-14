"""
配置文件
所有配置通过环境变量读取，敏感信息存储在 .env 文件中
"""
import os
from typing import Optional, List
from pydantic import field_validator
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # ==================== 环境配置 ====================
    ENVIRONMENT: str = "development"  # development, testing, production
    DEBUG: bool = True
    LOG_LEVEL: str = "INFO"

    # ==================== 应用配置 ====================
    APP_NAME: str = "复杂功能需求自动化拆分系统"
    APP_VERSION: str = "1.0.0"
    API_V1_PREFIX: str = "/api/v1"
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000

    # CORS配置 - 从字符串解析为列表
    CORS_ORIGINS_STR: str = (
        "http://localhost:3000,http://127.0.0.1:3000,"
        "http://localhost:5173,http://127.0.0.1:5173"
    )

    @property
    def CORS_ORIGINS(self) -> List[str]:
        """将逗号分隔的字符串转换为列表"""
        return [origin.strip() for origin in self.CORS_ORIGINS_STR.split(",") if origin.strip()]

    # ==================== 数据库配置 ====================
    # MySQL 配置
    DB_HOST: str = "localhost"
    DB_PORT: int = 3306
    DB_USER: str = "root"
    DB_PASSWORD: str = ""  # 通过环境变量设置
    DB_NAME: str = "agent_system"
    DB_POOL_SIZE: int = 10
    DB_MAX_OVERFLOW: int = 20
    DB_POOL_RECYCLE: int = 3600
    DB_ECHO: bool = False

    @property
    def DATABASE_URL(self) -> str:
        """构建同步数据库连接URL"""
        return f"mysql+pymysql://{self.DB_USER}:{self.DB_PASSWORD}@{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}?charset=utf8mb4"

    # ==================== LLM配置（支持OpenAI、通义千问等）====================
    LLM_API_KEY: Optional[str] = None  # 通过环境变量设置
    LLM_BASE_URL: str = "https://dashscope.aliyuncs.com/compatible-mode/v1"  # 默认通义千问
    LLM_MODEL: str = "qwen-coder-plus"  # 默认通义千问模型
    LLM_TEMPERATURE: float = 0.2
    LLM_MAX_TOKENS: int = 8000
    # ==================== LLM HTTP客户端配置 ====================
    LLM_MAX_CONNECTIONS: int = 50

    LLM_CONNECT_TIMEOUT_SECONDS: int = 20
    LLM_READ_TIMEOUT_SECONDS: int = 300
    LLM_WRITE_TIMEOUT_SECONDS: int = 30
    LLM_POOL_TIMEOUT_SECONDS: int = 30

    @field_validator("LLM_TEMPERATURE")
    def validate_temperature(cls, v):
        if not 0 <= v <= 2:
            raise ValueError("Temperature must be between 0 and 2")
        return v

    # ==================== 文件存储配置 ====================
    UPLOAD_DIR: str = "./uploads"

    # ==================== 安全配置 ====================
    SECRET_KEY: str = "your-secret-key-change-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440  # 24 小时

    # ==================== 对话 ====================
    # 创建对话时占位标题；预处理完成后由 Normalizer 产物写回 title
    CONVERSATION_PLACEHOLDER_TITLE: str = "新对话"

    # ==================== 健康检查 ====================
    HEALTH_CHECK_PATH: str = "/health"

    # ==================== 路径配置 ====================
    BASE_DIR: str = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    @property
    def LOG_DIR(self) -> str:
        """日志目录"""
        return os.path.join(self.BASE_DIR, "logs")

    @property
    def UPLOAD_DIR_ABSOLUTE(self) -> str:
        """上传目录绝对路径"""
        return os.path.join(self.BASE_DIR, self.UPLOAD_DIR.lstrip("./"))

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True
        extra = "ignore"


@lru_cache()
def get_settings() -> Settings:
    """获取配置的单例函数"""
    return Settings()


# 全局配置实例
settings = get_settings()


def create_directories():
    """创建必要的目录"""
    directories = [
        settings.LOG_DIR,
        settings.UPLOAD_DIR_ABSOLUTE,
    ]

    for directory in directories:
        os.makedirs(directory, exist_ok=True)
        # 创建 .gitkeep 文件
        gitkeep_file = os.path.join(directory, ".gitkeep")
        if not os.path.exists(gitkeep_file):
            with open(gitkeep_file, "w") as f:
                f.write("# Auto-generated directory\n")


def print_settings_summary():
    """打印配置摘要（安全地隐藏敏感信息）"""
    print("=" * 60)
    print(f"[启动] {settings.APP_NAME} v{settings.APP_VERSION}")
    print(f"[环境] {settings.ENVIRONMENT} | 调试: {settings.DEBUG}")
    print("-" * 60)

    # 数据库（隐藏密码）
    db_url = settings.DATABASE_URL
    if "@" in db_url:
        parts = db_url.split("@")
        user_part = parts[0]
        if ":" in user_part:
            user, password = user_part.split(":", 1)
            db_url = f"{user}:***@{parts[1]}"
    print(f"[DB] {db_url}")

    # LLM
    if settings.LLM_API_KEY:
        masked_key = settings.LLM_API_KEY[:8] + "..." + settings.LLM_API_KEY[-4:]
        print(f"[LLM] {masked_key}")
        print(f"   |- 服务: {settings.LLM_BASE_URL}")
        print(f"   |- 模型: {settings.LLM_MODEL}")
        print(f"   |- 温度: {settings.LLM_TEMPERATURE}")
        print(f"   `- 最大tokens: {settings.LLM_MAX_TOKENS}")
    else:
        print("[LLM] 未配置API密钥")

    # 应用
    print(f"[服务] http://{settings.API_HOST}:{settings.API_PORT}")
    print(f"[上传] {settings.UPLOAD_DIR_ABSOLUTE}")

    print("=" * 60)


if __name__ == "__main__":
    # 测试配置加载
    try:
        # 创建目录
        create_directories()

        # 打印配置摘要
        print_settings_summary()

        print("配置加载成功！")

    except Exception as e:
        print(f"❌ 配置加载失败: {e}")
        exit(1)
