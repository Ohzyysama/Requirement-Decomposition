export const API_MODULE = {
    // 认证相关接口
    AUTH: {
        LOGIN: '/api/v1/auth/token',
        REGISTER: '/api/v1/auth/register',
        GET_USER_INFO: '/api/v1/auth/me'
    },
    // 对话相关接口
    CONVERSATIONS: {
        BASE: '/api/v1/conversations'
    },
    // 协调器相关接口
    COORDINATOR: {
        START: '/api/v1/coordinator/start',
        STOP: '/api/v1/coordinator/stop',
        TASKS: '/api/v1/coordinator/tasks',
        TASK_CHOICE_GROUPS: '/api/v1/coordinator/config/task-choice-groups',
        REPORT_DOWNLOAD: '/api/v1/coordinator/tasks', // ★ 新增：拼接 /{task_id}/report/download
    }
}