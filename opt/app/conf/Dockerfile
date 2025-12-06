# ==================== 构建阶段：用Maven打包项目 ====================
# 基础镜像：带Maven的JDK 17（和你之前的环境一致，确保打包兼容性）
FROM maven:3.9-amazoncorretto-17-alpine AS builder
# 设置工作目录（容器内的项目路径）
WORKDIR /app

# 复制宿主机的pom.xml和src目录到容器内（构建依赖和源码）
COPY pom.xml .
COPY src ./src

# 打包项目（跳过测试，和你之前的打包命令一致）
RUN mvn clean package -Dmaven.test.skip=true -Dfile.encoding=UTF-8

# ==================== 运行阶段：用纯JDK镜像运行Jar包 ====================
# 基础镜像：轻量版JDK 17（仅运行，减少镜像体积）
FROM openjdk:17.0.2-jdk-slim-bullseye
# 设置工作目录
WORKDIR /app

# 从构建阶段复制打包好的Jar包到运行阶段（只复制最终产物，减小镜像体积）
RUN apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/java-backend-0.0.1-SNAPSHOT.jar app.jar

# 暴露项目端口（Spring Boot默认8080，若你改了端口需同步修改）
EXPOSE 8080

# 容器启动命令（运行Jar包）
ENTRYPOINT ["java", "-jar", "app.jar", "--spring.profiles.active=prod"]
