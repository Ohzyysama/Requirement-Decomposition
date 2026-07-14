<script setup lang="ts">
import { ref, reactive, computed } from 'vue'
import { User, Lock, View, Hide, Message } from '@element-plus/icons-vue'
import { ElMessage, FormRules } from 'element-plus'
import { useUserStore } from "@/stores/userStore" // 引入Pinia store
import router from "../router/index"

const userStore = useUserStore()
const showPassword = ref(false)
const showConfirmPassword = ref(false)
const loading = ref(false) // 添加加载状态

// 表单验证计算属性
const isEmailValid = computed(() => {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  return emailRegex.test(form.email)
})

const form = reactive({
  username: '',
  email: '',
  password: '',
  confirmPassword: '',
  full_name: '' // 添加全名字段（可选）
})

// 自定义验证器
const validateUsername = (rule: any, value: string, callback: any) => {
  if (!value) {
    callback(new Error('请输入用户名'))
  } else if (value.length < 3) {
    callback(new Error('用户名必须包含最少3个字符'))
  } else {
    callback()
  }
}

const validatePassword = (rule: any, value: string, callback: any) => {
  if (!value) {
    callback(new Error('请输入密码'))
  } else if (value.length < 6) {
    callback(new Error('密码必须包含最少6个字符'))
  } else {
    callback()
  }
}

const validateConfirmPassword = (rule: any, value: string, callback: any) => {
  if (!value) {
    callback(new Error('请确认密码'))
  } else if (value !== form.password) {
    callback(new Error('两次输入的密码不一致'))
  } else {
    callback()
  }
}

const validateEmail = (rule: any, value: string, callback: any) => {
  if (!value) {
    callback(new Error('请输入邮箱'))
  } else if (!isEmailValid.value) {
    callback(new Error('请输入有效的邮箱地址'))
  } else {
    callback()
  }
}

const rules = reactive<FormRules>({
  username: [
    { required: true, message: '请输入用户名', trigger: 'change' },
    { validator: validateUsername, trigger: 'change' }
  ],
  email: [
    { required: true, message: '请输入邮箱', trigger: 'change' },
    { validator: validateEmail, trigger: 'change' }
  ],
  password: [
    { required: true, message: '请输入密码', trigger: 'change' },
    { validator: validatePassword, trigger: 'change' }
  ],
  confirmPassword: [
    { required: true, message: '请确认密码', trigger: 'change' },
    { validator: validateConfirmPassword, trigger: 'change' }
  ]
})

// 注册按钮是否可用的计算属性
const isFormValid = computed(() => {
  return form.username.length >= 3 &&
      form.password.length >= 6 &&
      form.confirmPassword === form.password &&
      isEmailValid.value
})

async function handleSubmit() {
  loading.value = true

  try {
    // 准备注册数据
    const registerData = {
      username: form.username,
      email: form.email,
      password: form.password,
      full_name: form.full_name || undefined // 可选字段
    }

    // 调用注册方法
    const result = await userStore.register(registerData)

    if (result.success) {
      ElMessage({
        message: "注册成功！请登录账号",
        type: 'success',
      })
      await router.push({path: "/login"})
    } else {
      ElMessage({
        message: result.message || "注册失败",
        type: 'error',
      })
    }
  } catch (error) {
    console.error('注册失败:', error)
    ElMessage({
      message: "注册请求失败，请稍后重试",
      type: 'error',
    })
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="register-container">
    <el-card class="register-box">
      <!-- Logo -->
      <div class="logo">
        <img style="width: 25%;height: 25%" src="../assets/logo.svg" alt="AGENT-BOT"/>
      </div>

      <!-- Title -->
      <h1 class="title">注册账号</h1>

      <!-- Form -->
      <el-form
          :model="form"
          :rules="rules"
          label-position="top"
          @submit.prevent
      >
        <!-- Username Field -->
        <el-form-item prop="username" label="用户名" style="margin-bottom: 0.2rem">
          <el-input
              v-model="form.username"
              :prefix-icon="User"
              placeholder="请输入用户名"
              size="large"
          />
        </el-form-item>

        <!-- Email Field -->
        <el-form-item prop="email" label="邮箱" style="margin-bottom: 0.2rem">
          <el-input
              v-model="form.email"
              :prefix-icon="Message"
              placeholder="请输入邮箱"
              size="large"
          />
        </el-form-item>

        <!-- Password Field -->
        <el-form-item prop="password" label="密码" style="margin-bottom: 0.2rem">
          <el-input
              v-model="form.password"
              :prefix-icon="Lock"
              :type="showPassword ? 'text' : 'password'"
              placeholder="请输入密码"
              size="large"
          >
            <template #suffix>
              <el-icon class="cursor-pointer" @click="showPassword = !showPassword">
                <View v-if="showPassword" />
                <Hide v-else />
              </el-icon>
            </template>
          </el-input>
        </el-form-item>

        <!-- Confirm Password Field -->
        <el-form-item prop="confirmPassword" label="确认密码" style="margin-bottom: 0.2rem">
          <el-input
              v-model="form.confirmPassword"
              :prefix-icon="Lock"
              :type="showConfirmPassword ? 'text' : 'password'"
              placeholder="请确认密码"
              size="large"
          >
            <template #suffix>
              <el-icon class="cursor-pointer" @click="showConfirmPassword = !showConfirmPassword">
                <View v-if="showConfirmPassword" />
                <Hide v-else />
              </el-icon>
            </template>
          </el-input>
        </el-form-item>

        <!-- Full Name Field (Optional) -->
        <el-form-item label="全名（可选）" style="margin-bottom: 0.2rem">
          <el-input
              v-model="form.full_name"
              :prefix-icon="User"
              placeholder="请输入全名"
              size="large"
          />
        </el-form-item>

        <!-- Register Button -->
        <el-button
            type="primary"
            :loading="loading"
            round
            size="large"
            class="submit-btn"
            @click="handleSubmit"
            :disabled="!isFormValid || loading"
        >
          <span>{{ loading ? '注册中...' : '注册' }}</span>
        </el-button>

        <div class="msg">
          已有账号?
          <router-link to="/login">立即登录</router-link>
        </div>
      </el-form>
    </el-card>
  </div>
</template>

<style scoped>
.register-container {
  height: 100%;
  background-image: linear-gradient(to right, rgba(255, 167, 223, 0.62), rgba(62, 201, 255, 0.55));
}

.register-box {
  background-color: #fff;
  width: 450px;
  height: fit-content;
  max-height: 90vh;
  border-radius: 15px;
  padding: 50px;
  position: relative;
  left: 50%;
  top: 50%;
  transform: translate(-50%, -50%);
}

.logo {
  text-align: center;
  margin-bottom: 0.5rem;
}

.title {
  font-size: 1.875rem;
  font-weight: 600;
  text-align: center;
  color: rgba(0, 183, 255, 0.44);
  margin-bottom: 0.5rem;
}

.submit-btn {
  width: 100%;
  margin-top: 0.5rem;
}
.msg {
  text-align: center;
  line-height: 40px;
}
a {
  text-decoration-line: none;
  color: #409eff;
}

.cursor-pointer {
  cursor: pointer;
}

</style>