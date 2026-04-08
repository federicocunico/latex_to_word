import { createRouter, createWebHistory } from 'vue-router'
import ConverterView from '../views/ConverterView.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'converter',
      component: ConverterView,
    },
  ],
})

export default router
