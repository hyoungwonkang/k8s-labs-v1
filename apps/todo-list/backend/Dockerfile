FROM openjdk:temurin-17-jdk-alpine

WORKDIR /app

# Gradle Wrapper 파일 복사
COPY gradlew /app/gradlew
COPY gradle /app/gradle
RUN chmod +x ./gradlew

# 빌드 설정 파일 복사
COPY build.gradle /app/build.gradle
COPY settings.gradle /app/settings.gradle

# 의존성 미리 다운로드
RUN ./gradlew build --no-daemon --parallel --continue --stacktrace -x test || true

# 전체 소스 코드 복사 (실제 실행 시에는 볼륨으로 대체)
COPY . .

# 개발 환경에서는 디버깅 포트를 열어둡니다.
EXPOSE 8080

# 애플리케이션을 devtools 모드로 실행
CMD ["./gradlew", "bootRun"]
