1. 创建一个虚拟环境并激活（尽量用python 3.10.7 pip 25.3，其他可能有版本问题）

2. 安装依赖

3. 编辑.env文件，修改mysql和ai配置，mysql是账户密码，ai是密钥、接口地址、模型

   ```
   # DB_PASSWORD=你的MySQL密码
   # LLM_API_KEY=你的 API 密钥（与 app/core/config.py / .env.example 中变量名一致）
   ```
   获取API Key：
   https://help.aliyun.com/zh/model-studio/get-api-key?spm=5176.30275541.J_ZGek9Blx07Hclc3Ddt9dg.13.65d92f3dDYJFL1&scm=20140722.S_help@@%E6%96%87%E6%A1%A3@@2712195._.ID_help@@%E6%96%87%E6%A1%A3@@2712195-RL_apikey-LOC_2024SPAllResult-OR_ser-PAR1_213d63e317704413258957630d0cb6-V_4-PAR3_o-RE_new9-P0_3-P1_0

   查看免费额度：
   https://help.aliyun.com/zh/model-studio/new-free-quota?spm=a2ty02.30267245.0.0.36b874a1T9q7Df

4. 启动应用

   ```
   uvicorn app.main:app --reload
   ```

5. 验证安装（这个不行就试一下127.0.0.1:8000，0.0.0.0我不知道为啥一直是）

   1. 访问 http://localhost:8000/docs - API文档
   2. 访问 http://localhost:8000/health - 健康检查
   3. 访问 http://localhost:8000/test-db - 数据库测试

6. 初始化数据库

   1. 登录mysql
   2. 浏览器访问：http://localhost:8000/init-db

7. 调试
   1.   在http://localhost:8000/docs  先注册，再登录，拿到token（引号内内容）在右上角authen...处锁定，有效期差不多十分钟。先创建对话，随后用对话id创建任务，用start协调器开跑，最后看结果。
      status接口暂时有些状态问题
      传入对象参考
      ```
      {
         "title": "在线课程平台需求分析",
         "description": "测试模块三的统一编排能力",
         "original_requirement": "实现一个在线课程平台，支持学生注册登录、浏览课程列表、购买课程、观看视频，并提供作业提交和老师评分功能。"
      }
      ```
      ```
      {
         "conversation_id": "5f46823e-0a14-4b80-b00f-c427374161b7",
         "config": {
            "model": "qwen-coder-plus",
            "consistency_inner_max_retries": 1,
            "continue_pipeline_after_consistency_exhausted": false
         }
      }
      ```
      主任务完成后，可对功能树某节点补充拆分：`POST /api/v1/coordinator/tasks/{conversation_id}/refine-node`，body 含 `node_id`、可选 `user_instruction` 与 `config` 覆盖。
   2. 跑脚本做简单测试，在根目录下执行PYTHONPATH=. python scripts/run_m1_pipeline.py（mac，win可能不需要第一行，报错可能要用ai调整一下指令路径）

#### 项目结构说明

```
项目根目录/
├── app/                    # 应用代码
│   ├── api/               # API接口
│   ├── core/              # 核心配置
│   ├── models/            # 数据模型
│   ├── repositories/      # 数据访问
│   ├── services/          # 业务逻辑
│   └── utils/             # 工具函数
├── logs/                  # 日志目录（自动创建）
├── uploads/               # 上传文件目录（自动创建）
├── .env                   # 环境变量（需手动创建）
├── requirements.txt       # Python依赖
└── README.md             # 项目说明
```

