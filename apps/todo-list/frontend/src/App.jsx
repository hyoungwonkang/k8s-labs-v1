import React, { useState, useEffect } from 'react';
import {
  BrowserRouter as Router,
  Route,
  Routes,
  Navigate,
} from 'react-router-dom';
import LoginPage from './pages/LoginPage';
import SignupPage from './pages/SignupPage';
import TodoPage from './pages/TodoPage';

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(
    localStorage.getItem('isAuthenticated') === 'true'
  );

  useEffect(() => {
    const accessToken = localStorage.getItem('accessToken');
    if (accessToken) {
      setIsAuthenticated(true);
    } else {
      setIsAuthenticated(false); // accessToken이 없으면 로그인 상태가 아니라고 설정
    }
  }, []);

  useEffect(() => {
    localStorage.setItem('isAuthenticated', isAuthenticated);
  }, [isAuthenticated]);

  return (
    <Router>
      <Routes>
        {/* 로그인 페이지 */}
        <Route
          path="/login"
          element={<LoginPage setIsAuthenticated={setIsAuthenticated} />}
        />

        {/* 회원가입 페이지 */}
        <Route path="/signup" element={<SignupPage />} />

        {/* 인증된 경우에만 TodoPage로 이동, 그렇지 않으면 로그인 페이지로 이동 */}
        <Route
          path="/todos"
          element={isAuthenticated ? <TodoPage /> : <Navigate to="/login" />}
        />

        {/* 루트 경로에 대한 리다이렉트 */}
        <Route
          path="/"
          element={<Navigate to={isAuthenticated ? '/todos' : '/login'} />}
        />
      </Routes>
    </Router>
  );
}

export default App;
/* Test */
