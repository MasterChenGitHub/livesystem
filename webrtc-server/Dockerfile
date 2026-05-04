# 构建阶段基础镜像（Gradle + JDK17）
ARG GRADLE_IMAGE=docker.m.daocloud.io/library/gradle:9.4.0-jdk17
# 运行阶段基础镜像（仅 JRE，体积更小）
ARG RUNTIME_IMAGE=docker.m.daocloud.io/library/eclipse-temurin:17-jre

# ===== Stage 1: Build =====
# 使用 Gradle 镜像编译 Spring Boot 可执行 Jar
FROM ${GRADLE_IMAGE} AS build
# 统一工作目录
WORKDIR /workspace
# 复制项目源码到容器中
COPY . .
# 构建可执行 Jar（无守护进程，适合 CI/容器环境）
RUN gradle bootJar --no-daemon

# ===== Stage 2: Runtime =====
# 使用精简运行时镜像，仅保留启动所需内容
FROM ${RUNTIME_IMAGE}
# 应用运行目录
WORKDIR /app
# 从构建阶段复制产物 Jar 到运行镜像
COPY --from=build /workspace/build/libs/*.jar /app/app.jar
# 对外暴露服务端口（webrtc-server: 8081）
EXPOSE 8081
# 容器启动命令
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
