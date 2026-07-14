"""
数据库配置
"""
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

from app.core.config import settings

# 创建数据库引擎
engine = create_engine(
    settings.DATABASE_URL,
    pool_size=settings.DB_POOL_SIZE,
    max_overflow=settings.DB_MAX_OVERFLOW,
    pool_recycle=settings.DB_POOL_RECYCLE,
    echo=settings.DB_ECHO,
)

# 创建会话工厂
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# 创建基类
Base = declarative_base()


def get_db():
    """获取数据库会话"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """初始化数据库，创建所有表"""
    try:
        # 确保先导入所有模型
        from app.models.user import User
        from app.models.conversation import Conversation, Message
        from app.models.conversation_iteration import ConversationIteration

        print("=" * 50)
        print("正在创建数据库表...")

        # 打印要创建的表
        print("将创建以下表:")
        for table_name in Base.metadata.tables.keys():
            print(f"  - {table_name}")

        # 创建所有表（如果表已存在，不会重复创建）
        Base.metadata.create_all(bind=engine)

        print("✅ 表创建完成")

        # 验证表是否创建成功
        from sqlalchemy import inspect, text
        inspector = inspect(engine)
        created_tables = inspector.get_table_names()

        print("\n实际创建的表:")
        for table in created_tables:
            print(f"  - {table}")

        if len(created_tables) == 0:
            print("⚠️  警告：没有创建任何表！")
            print("可能原因:")
            print("1. 数据库连接失败")
            print("2. 用户没有创建表的权限")
            print("3. 表已经存在")
        else:
            print(f"\n✅ 成功创建了 {len(created_tables)} 个表")

    except Exception as e:
        print(f"❌ 数据库初始化失败: {e}")
        import traceback
        traceback.print_exc()
        raise