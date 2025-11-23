// api.js
import axios from 'axios';

const api = axios.create({
  baseURL: '/api',  // 상대 경로로 변경 - Vite proxy가 처리
});

export default api;