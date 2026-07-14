import axios from 'axios'
import { API_MODULE } from './_prefix.js'
import { consumeCoordinatorSseStream } from '@/utils/coordinatorSse.js'

/**
 * 对话相关API接口
 */
export const chatAPI = {
    /**
     * 分页/筛选参数（按后端支持传入）
     * @param {Record<string, string | number>} [params]
     */
    async listConversations(params = {}) {
        try {
            const response = await axios.get(API_MODULE.CONVERSATIONS.BASE, { params })
            return {
                success: true,
                data: response.data,
            }
        } catch (error) {
            console.error('获取对话列表失败:', error)
            const detail = error.response?.data?.detail
            const message =
                typeof detail === 'string'
                    ? detail
                    : Array.isArray(detail)
                      ? detail.map((d) => (typeof d?.msg === 'string' ? d.msg : JSON.stringify(d))).join('；')
                      : '获取对话列表失败'
            return {
                success: false,
                message,
            }
        }
    },

    /**
     * 创建新对话
     * @param {Object} conversationData - 对话数据
     * @returns {Promise<Object>} 创建的对话信息
     */
    async createConversation(conversationData) {
        try {
            const response = await axios.post(API_MODULE.CONVERSATIONS.BASE, conversationData)
            return {
                success: true,
                data: response.data
            }
        } catch (error) {
            console.error('创建对话失败:', error)
            const detail = error.response?.data?.detail
            const message =
                typeof detail === 'string'
                    ? detail
                    : Array.isArray(detail)
                      ? detail.map((d) => (typeof d?.msg === 'string' ? d.msg : JSON.stringify(d))).join('；')
                      : detail && typeof detail === 'object' && typeof detail.message === 'string'
                        ? detail.message
                        : '创建对话失败'
            return {
                success: false,
                message,
            }
        }
    },

    /**
     * 解析任务编排可选配置（三组键：重试 / 细化深度 / 耗尽后继续）
     * @returns {Promise<{ success: boolean, data?: object, message?: string }>}
     */
    async getCoordinatorTaskChoiceGroups() {
        try {
            const response = await axios.get(API_MODULE.COORDINATOR.TASK_CHOICE_GROUPS)
            return {
                success: true,
                data: response.data,
            }
        } catch (error) {
            console.error('获取解析任务配置项失败:', error)
            const detail = error.response?.data?.detail
            const message =
                typeof detail === 'string'
                    ? detail
                    : Array.isArray(detail)
                      ? detail.map((d) => (typeof d?.msg === 'string' ? d.msg : JSON.stringify(d))).join('；')
                      : '获取解析任务配置项失败'
            return {
                success: false,
                message,
            }
        }
    },

    /**
     * 启动协调器流程
     * @param {string} conversationId - 对话ID
     * @param {Object} config - 与后端 CoordinationRequest.config 对齐的可选片段
     * @returns {Promise<Object>} 任务信息
     */
    async startCoordinator(conversationId, config = {}) {
        try {
            const response = await axios.post(API_MODULE.COORDINATOR.START, {
                conversation_id: conversationId,
                config: config
            })
            return {
                success: true,
                data: response.data
            }
        } catch (error) {
            console.error('启动协调器失败:', error)
            return {
                success: false,
                message: error.response?.data?.detail || '启动协调器失败'
            }
        }
    },

    /**
     * 协作式停止当前编排（主任务或 refine-node）
     * @param {string} taskId - 与 conversation_id 相同
     */
    async stopCoordinator(taskId) {
        try {
            const response = await axios.post(
                `${API_MODULE.COORDINATOR.STOP}/${encodeURIComponent(taskId)}`
            )
            return {
                success: true,
                data: response.data,
            }
        } catch (error) {
            console.error('停止协调任务失败:', error)
            const detail = error.response?.data?.detail
            const message =
                typeof detail === 'string'
                    ? detail
                    : Array.isArray(detail)
                      ? detail.map((d) => (typeof d?.msg === 'string' ? d.msg : JSON.stringify(d))).join('；')
                      : detail && typeof detail === 'object' && typeof detail.message === 'string'
                        ? detail.message
                        : '停止协调任务失败'
            return {
                success: false,
                message,
            }
        }
    },

    /**
     * 对功能树某节点发起重拆（需已有 final_result）
     * @param {string} taskId - 与 conversation_id 相同
     * @param {{ node_id: string, user_instruction?: string, config?: object }} body
     */
    async refineCoordinatorNode(taskId, body) {
        try {
            const response = await axios.post(
                `${API_MODULE.COORDINATOR.TASKS}/${encodeURIComponent(taskId)}/refine-node`,
                body
            )
            return {
                success: true,
                data: response.data,
            }
        } catch (error) {
            console.error('节点重拆启动失败:', error)
            const detail = error.response?.data?.detail
            const message =
                typeof detail === 'string'
                    ? detail
                    : Array.isArray(detail)
                      ? detail.map((d) => (typeof d?.msg === 'string' ? d.msg : JSON.stringify(d))).join('；')
                      : detail && typeof detail === 'object' && typeof detail.message === 'string'
                        ? detail.message
                        : '节点重拆启动失败'
            return {
                success: false,
                message,
            }
        }
    },

    /**
     * 监听协调任务 SSE（命名事件 + Bearer）
     * @param {string} conversationId
     * @param {{ signal: AbortSignal, onEvent: (eventName: string, data: object) => void }} options
     * @returns {Promise<void>} 流正常结束或中止时 resolve；仅 fetch/读流失败时 reject
     */
    listenTaskProgress(conversationId, options) {
        const base = axios.defaults.baseURL || ''
        const path = `${API_MODULE.COORDINATOR.TASKS}/${conversationId}/stream`
        const streamUrl = `${base.replace(/\/$/, '')}${path}`
        return consumeCoordinatorSseStream(streamUrl, options)
    },

    /**
     * 获取对话详情
     * @param {string} conversationId - 对话ID
     * @returns {Promise<Object>} 对话详情
     */
    async getConversationDetail(conversationId) {
        try {
            const response = await axios.get(`${API_MODULE.CONVERSATIONS.BASE}/${conversationId}`)
            return {
                success: true,
                data: response.data
            }
        } catch (error) {
            console.error('获取对话详情失败:', error)
            return {
                success: false,
                message: error.response?.data?.detail || '获取对话详情失败'
            }
        }
    },

    /**
     * 删除对话（成功时通常为 HTTP 204，无响应体）
     * @param {string} conversationId
     */
    async deleteConversation(conversationId) {
        try {
            await axios.delete(`${API_MODULE.CONVERSATIONS.BASE}/${encodeURIComponent(conversationId)}`)
            return { success: true }
        } catch (error) {
            console.error('删除对话失败:', error)
            const detail = error.response?.data?.detail
            const message =
                typeof detail === 'string'
                    ? detail
                    : Array.isArray(detail)
                      ? detail.map((d) => (typeof d?.msg === 'string' ? d.msg : JSON.stringify(d))).join('；')
                      : detail && typeof detail === 'object' && typeof detail.message === 'string'
                        ? detail.message
                        : '删除对话失败'
            return {
                success: false,
                message,
            }
        }
    },

    // ★ 新增：下载指定类型的分析报告（Markdown 文件）
    /**
     * 触发服务端生成某类 Markdown 报告并在浏览器中下载。
     * @param {string} taskId   - 对话/任务 ID
     * @param {string} type     - 报告类型：decomposition | consistency | granularity | feasibility
     * @returns {Promise<{ success: boolean, message?: string }>}
     */
    async downloadReport(taskId, type = 'decomposition') {
        try {
            const response = await axios.get(
                `${API_MODULE.COORDINATOR.REPORT_DOWNLOAD}/${taskId}/report/download`,
                { params: { type }, responseType: 'blob' }
            )
            // 从 Content-Disposition 提取文件名，兜底用 type + taskId
            const disposition = response.headers['content-disposition'] || ''
            const labelMap = {
                decomposition: '需求切分结果',
                consistency:   '一致性评估报告',
                granularity:   '粒度评估报告',
                feasibility:   '可实现性评估报告',
            }
            let filename = `${labelMap[type] ?? type}-${taskId.slice(0, 8)}.md`
            const utf8Match = disposition.match(/filename\*=UTF-8''(.+)/)
            if (utf8Match) {
                filename = decodeURIComponent(utf8Match[1])
            } else {
                const plainMatch = disposition.match(/filename="?([^";\n]+)"?/)
                if (plainMatch) filename = plainMatch[1]
            }
            const url = URL.createObjectURL(new Blob([response.data], { type: 'text/markdown;charset=utf-8' }))
            const a = document.createElement('a')
            a.href = url
            a.download = filename
            a.rel = 'noopener'
            a.click()
            URL.revokeObjectURL(url)
            return { success: true }
        } catch (error) {
            console.error('下载报告失败:', error)
            const detail = error.response?.data?.detail
            const message =
                typeof detail === 'string'
                    ? detail
                    : '下载报告失败，请稍后重试'
            return { success: false, message }
        }
    },

    /** 导出标准 AR 格式需求文档（Markdown） */
    async downloadArReport(taskId) {
        try {
            const response = await axios.get(
                `${API_MODULE.COORDINATOR.REPORT_DOWNLOAD}/${taskId}/report/ar-markdown`,
                { responseType: 'blob' }
            )
            const disposition = response.headers['content-disposition'] || ''
            let filename = `AR需求列表-${taskId.slice(0, 8)}.md`
            const utf8Match = disposition.match(/filename\*=UTF-8''(.+)/)
            if (utf8Match) {
                filename = decodeURIComponent(utf8Match[1])
            } else {
                const plainMatch = disposition.match(/filename="?([^";\n]+)"?/)
                if (plainMatch) filename = plainMatch[1]
            }
            const url = URL.createObjectURL(new Blob([response.data], { type: 'text/markdown;charset=utf-8' }))
            const a = document.createElement('a')
            a.href = url
            a.download = filename
            a.rel = 'noopener'
            a.click()
            URL.revokeObjectURL(url)
            return { success: true }
        } catch (error) {
            console.error('导出 AR 报告失败:', error)
            const detail = error.response?.data?.detail
            const message = typeof detail === 'string' ? detail : '导出 AR 报告失败，请稍后重试'
            return { success: false, message }
        }
    },
}

// 导出默认实例
export default chatAPI
