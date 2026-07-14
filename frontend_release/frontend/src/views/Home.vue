<script setup lang="ts">
import router from "../router/index"
import { useUserStore } from "@/stores/userStore" // 引入Pinia store
import {ElMessage, ElMessageBox} from "element-plus";
import { ArrowLeft } from '@element-plus/icons-vue'
import { computed } from 'vue'
import { useRoute } from 'vue-router'

const route = useRoute()
const userStore = useUserStore()

const activeMenu = computed(() => {
  const path = route.path
  if (path.startsWith('/chat')) return '/chat'
  return '/'
})

const username = computed(() => {
  const u = userStore.user
  return u?.username ?? u?.full_name ?? '用户'
})


async function logout() {
  ElMessageBox.confirm(
      '是否要退出登录？',
      '提示',
      {
        customClass: "customDialog",
        confirmButtonText: '是',
        cancelButtonText: '否',
        type: "warning",
        showClose: false,
        roundButton: true,
        center: true
      }
  ).then(() => {
    try {
      userStore.logout()
      ElMessage({
        message: "退出登录成功",
        type: 'success',
      })
      router.push({ path: "/login" })
    } catch (error) {
      ElMessage({
        message: "退出登录失败，请稍后重试",
        type: 'error',
      })
      console.error('退出登录失败:', error)
    }
  }).catch(error => {
    console.error('退出登录失败:', error)
  })
}


const goBack = () => {
  router.back()
}
</script>

<template>
  <div class="main-container">
    <div class="common-layout">
      <el-container>
        <el-header>
          <el-page-header @back="goBack" :icon="ArrowLeft" class="custom-header">
            <template #title>
              <span class="custom-header-title">返回</span>
            </template>
            <template #content>
              <img src="../assets/logo.svg" class="logo" alt="">
            </template>
            <template #extra>
              <el-space :size="25">
                <el-space :size="20">
                  <img src="../assets/logo.svg" alt="user" class="playerAvatar" />
                  <span style="color: black;">{{ username }}</span>
                </el-space>
                <el-button type="danger" @click="logout" round>退出</el-button>
              </el-space>
            </template>
          </el-page-header>
        </el-header>

        <el-container style="height: calc(100vh - 80px)">
<!--          <el-aside width="10%" height="100%">-->
<!--            <el-menu-->
<!--                :default-active="activeMenu"-->
<!--                background-color="#545c64"-->
<!--                text-color="#ffffff"-->
<!--                active-text-color="#ffd04b"-->
<!--                router-->
<!--            >-->
<!--              <el-menu-item index="/chat">chat</el-menu-item>-->
<!--            </el-menu>-->
<!--          </el-aside>-->
          <el-container>
            <el-main>
              <router-view />
            </el-main>
          </el-container>
        </el-container>
      </el-container>
    </div>
  </div>
</template>

<style scoped>
.custom-header {
  --el-page-header-text-color: black; /* Element Plus v2 支持的 CSS 变量 */
}

.custom-header-title {
  color: black;
}

.custom-header .el-page-header__left .el-icon {
  color: black;
}

.main-container {
  height: 100%;
  width: 100%;
  background-image: linear-gradient(to right, rgba(255, 167, 223, 0.62), rgba(62, 201, 255, 0.55));
}


.el-header {
  background: lightgrey;
  height: 80px;        /* 强制设置高度 */
  display: flex;
  justify-content: center;        /* 水平居中 */
  align-items: center;            /* 垂直居中 */
  padding: 0 0;
  box-sizing: border-box;         /* 包含 padding 在高度内 */
}

/* 子容器设置 */
.el-page-header {
  width: 85% ;          /* 保持原有宽度比例 */
  justify-content: space-between;
  align-items: center;            /* 内部元素垂直居中 */
  min-width: 0;
}

/* 调整内部元素高度 */
.el-page-header__extra {
  height: 100%;                   /* 继承父容器高度 */
  display: flex;
  align-items: center;            /* 内容垂直居中 */
}
.playerAvatar {
  border-radius: 50%;
  height: 50px;
}
/* 右侧操作区 */
.el-page-header__extra .el-space {
  font-size:20px;
  font-weight: 600;
  height: 100%;                  /* 继承父容器高度 */
  align-items: center;           /* 按钮垂直居中 */
}

.el-page-header__extra .el-space .el-button {
  font-size:20px;
}
/* 自定义 logo 适配 */
.logo {
  height: 50px;                  /* 按比例放大 logo */
  width: auto;                   /* 保持原始宽高比 */
}
.el-aside {
  background: #545c64;
}

.el-main {
  background: white;
}


</style>
