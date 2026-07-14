import { createRouter, createWebHistory } from 'vue-router'
import Login from '@/views/login.vue'
import register from '@/views/register.vue'
import Home from '@/views/home.vue'
import Chat from '@/components/chat.vue'
import EvaluationReport from "@/components/evaluation/EvaluationReport.vue";
import FunctionTree from "@/components/function/FunctionTree.vue";
import FunctionNode from "@/components/function/FunctionNode.vue";


const routes = [
    {
        path: '/',
        redirect: '/home'
    },
    {
        path: '/login',
        component: Login,
    },
    {
        path: '/register',
        component: register
    },
    {
        path: '/home',
        component: Home,
        redirect: '/chat',
        children: [
            {
                path: '/chat',
                component: Chat
            },
            {
                path: '/evaluation',
                component: EvaluationReport
            },
            {
                path: '/functionTree',
                component: FunctionTree
            },
            {
                path: '/functionNode',
                component: FunctionNode
            }
        ]
    },

]

const router = createRouter({
    history: createWebHistory(),
    routes
})
router.beforeEach((to, _, next) => {
    // `to` 表示即将要进入的目标路由对象
    // `_` 是当前导航正要离开的路由对象，这里用不到，所以用下划线占位
    // `next` 是一个函数，用于控制路由的跳转

    // 从 localStorage 中获取用户的 token
    const token= localStorage.getItem('auth_token');

    // 如果用户已经登录（即存在 token）
    if (token) {
        //允许跳转
        next();
    } else {
        // 如果用户未登录
        if (to.path === '/login') {
            // 如果目标路由是登录页面，允许路由跳转
            next();
        } else if (to.path === '/register') {
            // 如果目标路由是注册页面，允许路由跳转
            next();
        } else {
            // 如果目标路由不是登录页面也不是注册页面，跳转到登录页面
            next('/login');
        }
    }
});
export default router
