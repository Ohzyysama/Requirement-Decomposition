import axios from 'axios'
import { API_MODULE } from "./_prefix.js";

/** FastAPI 错误 detail 可能是 string | { msg }[] | 其他，统一成可读文案 */
function formatFastApiDetail(detail) {
    if (detail == null) return ''
    if (typeof detail === 'string') return detail
    if (Array.isArray(detail)) {
        return detail
            .map((item) => {
                if (typeof item === 'string') return item
                if (item && typeof item.msg === 'string') return item.msg
                try {
                    return JSON.stringify(item)
                } catch {
                    return String(item)
                }
            })
            .filter(Boolean)
            .join('；')
    }
    if (typeof detail === 'object' && typeof detail.msg === 'string') return detail.msg
    try {
        return JSON.stringify(detail)
    } catch {
        return String(detail)
    }
}

// 请求拦截器 - 自动添加token
axios.interceptors.request.use(
    (config) => {
        const token = localStorage.getItem('auth_token')
        if (token) {
            config.headers.Authorization = `Bearer ${token}`
        }
        return config
    },
    (error) => {
        return Promise.reject(error)
    }
)

// 响应拦截器 - 处理认证错误
axios.interceptors.response.use(
    (response) => {
        return response
    },
    (error) => {
        if (error.response?.status === 401) {
            // token过期或无效，清除本地存储
            localStorage.removeItem('auth_token')
            localStorage.removeItem('user_info')
            // 可以跳转到登录页
            window.location.href = '/login'
        }
        return Promise.reject(error)
    }
)

/**
 * 用户登录
 * @param {Object} credentials - 登录凭据
 * @param {string} credentials.username - 用户名
 * @param {string} credentials.password - 密码
 * @returns {Promise<Object>} 登录结果
 */
export const userLogin = async (credentials) => {
    try {
        // 后端要求 application/json，而非表单编码
        const response = await axios.post(API_MODULE.AUTH.LOGIN, {
            username: credentials.username,
            password: credentials.password
        })

        if (response.data.access_token) {
            // 保存token到localStorage
            localStorage.setItem('auth_token', response.data.access_token)

            // 获取用户信息并保存
            const userInfo = await getUserInfo()
            localStorage.setItem('user_info', JSON.stringify(userInfo))

            return {
                success: true,
                data: userInfo,
                message: '登录成功'
            }
        }

        return {
            success: false,
            message: '登录响应异常，未返回访问令牌'
        }
    } catch (error) {
        console.error('登录失败:', error)
        const detailText = formatFastApiDetail(error.response?.data?.detail)
        return {
            success: false,
            message: detailText || '登录失败，请检查用户名和密码'
        }
    }
}

/**
 * 用户注册
 * @param {Object} userData - 用户注册数据
 * @param {string} userData.username - 用户名
 * @param {string} userData.email - 邮箱
 * @param {string} userData.password - 密码
 * @param {string} userData.full_name - 全名（可选）
 * @returns {Promise<Object>} 注册结果
 */
export const userRegister = async (userData) => {
    try {
        const payload = {
            username: userData.username,
            email: userData.email,
            password: userData.password
        }
        if (userData.full_name) payload.full_name = userData.full_name

        const response = await axios.post(API_MODULE.AUTH.REGISTER, payload)

        return {
            success: true,
            data: response.data,
            message: '注册成功'
        }
    } catch (error) {
        if (!error.response) {
            return {
                success: false,
                message:
                    error.code === 'ERR_NETWORK'
                        ? '无法连接服务器，请确认后端已启动且地址与 main.js 中 axios.defaults.baseURL 一致'
                        : '注册请求失败，请稍后重试'
            }
        }

        const detailText = formatFastApiDetail(error.response.data?.detail)
        const lower = detailText.toLowerCase()

        let errorMessage = '注册失败，请稍后重试'
        if (detailText) {
            if (
                lower.includes('username') &&
                (lower.includes('already') || lower.includes('taken') || lower.includes('exist'))
            ) {
                errorMessage = '用户名已存在'
            } else if (
                lower.includes('email') &&
                (lower.includes('already') || lower.includes('taken') || lower.includes('exist'))
            ) {
                errorMessage = '邮箱已注册'
            } else {
                errorMessage = detailText
            }
        }

        return {
            success: false,
            message: errorMessage
        }
    }
}

/**
 * 获取当前用户信息
 * @returns {Promise<Object>} 用户信息
 */
export const getUserInfo = async () => {
    try {
        const response = await axios.get(API_MODULE.AUTH.GET_USER_INFO)
        return response.data
    } catch (error) {
        console.error('获取用户信息失败:', error)
        throw error
    }
}

/**
 * 用户退出登录
 */
export const userLogout = () => {
    localStorage.removeItem('auth_token')
    localStorage.removeItem('user_info')
}

/**
 * 检查用户是否已登录
 * @returns {boolean} 是否已登录
 */
export const isAuthenticated = () => {
    return !!localStorage.getItem('auth_token')
}

/**
 * 获取当前用户信息（从本地存储）
 * @returns {Object|null} 用户信息
 */
export const getCurrentUser = () => {
    const userInfo = localStorage.getItem('user_info')
    return userInfo ? JSON.parse(userInfo) : null
}
