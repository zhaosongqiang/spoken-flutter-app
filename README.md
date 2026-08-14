# 声动AI口语 Flutter App

Open Design `Mobile App` 的 Flutter 实现，支持 iOS 15+ 和 Web，连接同仓库的 `spoken-server`。

## 本地运行

后端默认地址为 `http://localhost:8080`。Flutter Web 固定使用 5174 端口，以匹配服务端本地 CORS 配置。
客户端会在该地址后自动追加统一的 `/api/v1` 接口前缀，因此
`API_BASE_URL` 只需配置协议、域名和端口，不要包含 `/api/v1`。
服务端的 `/api` 由 Spring MVC 统一添加，版本 `/v1` 声明在各 Controller 的
`@RequestMapping` 上。

修改服务端 CORS 配置后需要重启 `spoken-server`；也可以通过
`SPOKEN_CORS_ALLOWED_ORIGINS` 传入逗号分隔的 Web 来源。

```bash
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"

flutter pub get
flutter run -d chrome --web-port 5174 --dart-define=API_BASE_URL=http://localhost:8080
flutter run -d ios --dart-define=API_BASE_URL=http://localhost:8080
```

真机联调时将 `API_BASE_URL` 改为可由 iPhone 访问的 HTTPS 或局域网地址。

Web 浏览器可能忽略录音时请求的 16kHz 采样率并输出 48kHz。客户端会在录音停止后、
上传评分前解析 WAV，并统一转换为 PCM16、16000Hz、mono；iOS 录音文件保持原样。

## 验证

```bash
flutter analyze
flutter test
flutter test --platform chrome test/wav_pcm16_test.dart
flutter build web --release --dart-define=API_BASE_URL=http://192.168.0.62:8080
flutter build ios --simulator --dart-define=API_BASE_URL=http://localhost:8080
```

本机 Flutter SDK 安装在 `/Users/zhaosongqiang/development/flutter`。若当前 shell
尚未配置 PATH，可将上述命令中的 `flutter` 替换为
`/Users/zhaosongqiang/development/flutter/bin/flutter`。

## 公网部署

生产环境不要使用 `flutter run` 对外提供服务。Flutter Web 应先编译为静态资源，
再通过 Nginx、对象存储/CDN、Cloudflare Pages、Firebase Hosting 等平台托管。
构建结果位于 `build/web`，具体可参考
[Flutter Web 官方部署文档](https://docs.flutter.dev/deployment/web)。

推荐让 Flutter 页面和后端接口使用同一个域名，由 Nginx 将接口请求转发到只在
本机监听的 `spoken-server`：

```text
https://spoken.example.com/             Flutter Web
https://spoken.example.com/api/v1/...   Nginx 转发到 127.0.0.1:8080
```

使用正式域名构建 Web release：

```bash
flutter build web --release \
  --dart-define=API_BASE_URL=https://spoken.example.com
```

`API_BASE_URL` 是编译期参数，更换接口域名后需要重新构建。构建完成后，将
`build/web` 目录中的文件上传到 Web 服务器的静态资源目录。

### Nginx 示例

下面的配置使用同域反向代理，因此浏览器访问业务接口时不需要额外配置 CORS：

```nginx
server {
    listen 443 ssl http2;
    server_name spoken.example.com;

    root /var/www/spoken;
    index index.html;

    client_max_body_size 20m;

    location /api/v1/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 180s;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

TLS 证书、证书私钥路径以及 HTTP 到 HTTPS 的跳转应根据实际服务器环境补充。
如果前端和 API 使用不同域名，需要将前端的完整 HTTPS Origin 加入
`SPOKEN_CORS_ALLOWED_ORIGINS`，保留 credentials 支持，并重启服务端。

### 上线检查清单

- 全站使用 HTTPS。浏览器麦克风录音只允许在 HTTPS 等安全上下文中使用，详见
  [MDN getUserMedia 安全要求](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)。
- 生产环境设置 `ACCOUNT_COOKIE_SECURE=true`，并使用合理的 Cookie Domain 和
  SameSite 策略。
- 不直接向公网暴露 `spoken-server` 的 8080 端口，只允许反向代理访问。
- 将数据库、语音评分、AI、TTS 和 OSS 密钥迁移到环境变量或密钥管理服务；轮换
  任何曾经进入代码库或日志的生产密钥。
- 为语音评分、AI 点评和 TTS 增加账号配额、接口频率限制、并发限制和防滥用策略，
  避免匿名试用账号产生不可控的第三方服务费用。
- 配置访问日志、错误监控、服务健康检查、告警和数据库备份。
- 发布前执行 `flutter analyze`、`flutter test` 和 Web release 构建，并在主流桌面及
  移动浏览器上验证麦克风授权、录音提交、音频播放、历史记录和 AI 反馈闭环。
