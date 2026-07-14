import { defineStore } from 'pinia'
import { ref } from 'vue'
import { userLogin, userRegister, getUserInfo, isAuthenticated, getCurrentUser } from '@/api/user'

export const useUserStore = defineStore('user', () => {
    const user = ref(getCurrentUser())
    const isLoggedIn = ref(isAuthenticated())
    const loading = ref(false)

    // 登录操作
    const login = async (credentials) => {
        loading.value = true
        try {
            const result = await userLogin(credentials)

            if (result.success) {
                user.value = result.data
                isLoggedIn.value = true
                return { success: true, message: result.message }
            } else {
                return { success: false, message: result.message }
            }
        } catch (error) {
            return { success: false, message: '登录过程中发生错误' }
        } finally {
            loading.value = false
        }
    }

    // 注册操作
    const register = async (userData) => {
        loading.value = true
        try {
            const result = await userRegister(userData)

            if (result.success) {
                return { success: true, message: result.message }
            } else {
                return { success: false, message: result.message }
            }
        } catch (error) {
            return { success: false, message: '注册过程中发生错误' }
        } finally {
            loading.value = false
        }
    }

    // 退出登录
    const logout = () => {
        user.value = null
        isLoggedIn.value = false
        localStorage.removeItem('auth_token')
        localStorage.removeItem('user_info')
    }

    // 检查登录状态
    const checkAuth = () => {
        isLoggedIn.value = isAuthenticated()
        if (isLoggedIn.value) {
            user.value = getCurrentUser()
        }
    }

    return {
        user,
        isLoggedIn,
        loading,
        login,
        register,
        logout,
        checkAuth
    }
})