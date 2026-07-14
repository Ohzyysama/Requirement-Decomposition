import './assets/main.css'

import { createApp } from 'vue'
import App from './App.vue'
import axios from 'axios'
import '@/api/user'
import router from "@/router/index.js";import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css';
import * as ElementPlusIconsVue from '@element-plus/icons-vue'
import { createPinia } from 'pinia';


// 设置全局axios默认值
axios.defaults.baseURL = 'http://localhost:8000'
sessionStorage.setItem("web", axios.defaults.baseURL)
// 允许携带cookie

// axios.defaults.withCredentials = true  // 使用 Bearer Token 无需携带 cookie

const app = createApp(App)
const pinia = createPinia();
app.use(pinia);

app.use(router)
    .use(ElementPlus)
for (const [key, component] of Object.entries(ElementPlusIconsVue)) {
    app.component(key, component)
}

app.mount('#app')
