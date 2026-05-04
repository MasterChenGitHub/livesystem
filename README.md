# LiveSystem

一个包含 Flutter 客户端 + Spring Boot API + WebRTC 信令服务 + Nginx 反向代理 + Coturn 的实时通信系统。

## 项目结构

- [jokes](jokes) Flutter App（聊天、语音/视频通话）
- [myapi](myapi) Spring Boot 业务 API（消息、上传凭证等）
- [webrtc-server](webrtc-server) WebRTC 信令与 ICE 配置下发
- [deploy](deploy) Docker Compose 与 Nginx 配置
- [MESSAGE_SYSTEM_GUIDE.md](MESSAGE_SYSTEM_GUIDE.md) 消息系统说明
- [oss-config.properties](oss-config.properties) OSS 外部配置（已从应用内抽离）

## 快速开始（本地）

### 1) 启动后端依赖（推荐 Docker）

在项目根目录执行：

- `docker compose -f deploy/docker-compose.yml up -d mysql redis`

### 2) 启动 myapi

在 [myapi](myapi) 目录执行：

- `./gradlew bootRun`

### 3) 启动 webrtc-server

在 [webrtc-server](webrtc-server) 目录执行：

- `./gradlew bootRun`

### 4) 启动 Flutter 客户端

在 [jokes](jokes) 目录执行：

- `flutter pub get`
- `flutter run`

可通过 Dart Define 覆盖地址：

- `--dart-define=API_BASE_URL=http://<host>/api`
- `--dart-define=WEBRTC_SERVER_URL=http://<host>`

## 生产部署（Docker Compose）

部署入口脚本：

- [deploy/deploy_new_server.sh](deploy/deploy_new_server.sh)

核心编排文件：

- [deploy/docker-compose.yml](deploy/docker-compose.yml)

Nginx 反代配置：

- [deploy/nginx/default.conf](deploy/nginx/default.conf)

## OSS 配置（已抽离）

OSS 参数统一放在根目录：

- [oss-config.properties](oss-config.properties)

myapi 会通过 `spring.config.import` 自动加载该文件（同时兼容容器内 `/app/oss-config.properties` 挂载路径）。

配置文件示例（Demo）：

```properties
# /livesystem/oss-config.properties
aliyun.oss.endpoint=oss-cn-shenzhen.aliyuncs.com
aliyun.oss.access-key-id=your-access-key-id
aliyun.oss.access-key-secret=your-access-key-secret
aliyun.oss.bucket=your-bucket-name
aliyun.oss.public-url-prefix=https://your-bucket-name.oss-cn-shenzhen.aliyuncs.com/
```

容器部署时，`myapi` 会通过 [deploy/docker-compose.yml](deploy/docker-compose.yml) 中的 volume 挂载读取该文件。

建议：

1. 使用 RAM 子账号最小权限 AK。
2. 不要在公开仓库提交真实密钥。
3. 生产环境通过 CI/密钥管理系统注入该文件。

## WebRTC / TURN 注意事项

当前 Coturn 使用 `host` 网络模式以避免 Docker NAT 破坏 ICE 地址映射。

阿里云安全组需放通：

- TCP `3478`
- UDP `3478`
- UDP `49160-49200`

## License

仅用于学习与内部项目演示，请根据实际需求补充开源协议。
