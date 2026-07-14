"""
应用主入口
"""
import sys
import os
from pathlib import Path

# 添加项目根目录到Python路径
sys.path.append(str(Path(__file__).parent.parent))

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# 导入配置
from app.core.config import settings, create_directories, print_settings_summary


def create_app() -> FastAPI:
    """创建FastAPI应用"""

    # 创建必要的目录
    create_directories()

    # 打印配置摘要
    print_settings_summary()

    # 创建FastAPI应用
    app = FastAPI(
        title=settings.APP_NAME,
        version=settings.APP_VERSION,
        debug=settings.DEBUG,
        docs_url="/docs" if settings.DEBUG else None,
        redoc_url="/redoc" if settings.DEBUG else None,
    )

    # 添加CORS中间件
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # 导入并注册路由（分项注册，避免某一模块导入失败导致全部 API 丢失）
    def _safe_include(name: str, import_fn, prefix: str, tag: str) -> None:
        try:
            router = import_fn()
            app.include_router(router, prefix=prefix, tags=[tag])
            print(f"✅ 路由已注册: {name} ({prefix})")
        except ImportError as e:
            print(f"⚠️  路由 [{name}] 导入失败: {e}")

    p = settings.API_V1_PREFIX.rstrip("/")
    _safe_include(
        "auth",
        lambda: __import__("app.api.auth", fromlist=["router"]).router,
        f"{p}/auth",
        "认证",
    )
    _safe_include(
        "conversation",
        lambda: __import__("app.api.conversation", fromlist=["router"]).router,
        f"{p}/conversations",
        "对话",
    )
    _safe_include(
        "coordinator",
        lambda: __import__("app.api.coordinator", fromlist=["router"]).router,
        f"{p}/coordinator",
        "协调器",
    )

    # 健康检查端点
    @app.get(settings.HEALTH_CHECK_PATH)
    async def health_check():
        return {
            "status": "healthy",
            "app": settings.APP_NAME,
            "version": settings.APP_VERSION,
            "environment": settings.ENVIRONMENT,
        }

    # 数据库测试端点
    @app.get("/test-db")
    async def test_db():
        try:
            # 测试数据库连接
            from sqlalchemy import text
            from app.core.database import SessionLocal
            with SessionLocal() as session:
                result = session.execute(text("SELECT 1"))
                return {"database": "connected", "result": result.scalar()}
        except Exception as e:
            return {"database": "error", "message": str(e)}

    # 数据库初始化端点（仅开发环境使用）
    @app.api_route("/init-db", methods=["GET", "POST"])
    async def initialize_database():
        if settings.ENVIRONMENT != "production":
            try:
                from app.core.database import init_db
                init_db()
                return {"message": "Database initialized successfully"}
            except Exception as e:
                return {"message": f"Database initialization failed: {str(e)}"}
        return {"message": "Database initialization not allowed in production"}

    # 根端点
    @app.get("/")
    async def root():
        return {
            "app": settings.APP_NAME,
            "version": settings.APP_VERSION,
            "docs": "/docs",
            "health": settings.HEALTH_CHECK_PATH
        }

    return app


# 创建应用实例
app = create_app()


if __name__ == "__main__":
    print(f"🚀 启动 {settings.APP_NAME} v{settings.APP_VERSION}")
    print(f"📡 服务运行在: http://{settings.API_HOST}:{settings.API_PORT}")
    print(f"📚 API文档: http://{settings.API_HOST}:{settings.API_PORT}/docs")

    uvicorn.run(
        app,
        host=settings.API_HOST,
        port=settings.API_PORT,
        log_level=settings.LOG_LEVEL.lower(),
        reload=settings.DEBUG,
    )