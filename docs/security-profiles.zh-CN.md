# 安全档位与平滑迁移

## 推荐默认方案

现有部署默认保持 `lan` 档位。该档位保留历史行为，适合家庭内网、NAS、软路由、旁路由、Docker 内网等自用部署，用户仍可通过项目访问本地资源、私有网段资源和 fake-ip 资源。

公网部署建议显式切到 `public`：

```ini
[security]
profile=public
```

或使用环境变量：

```bash
SUBCONVERTER_SECURITY_PROFILE=public
```

## 三个档位

- `lan`：默认值，兼容旧行为。公开请求、外部配置、规则集、订阅链接仍可访问本地、私有网段和 fake-ip 资源。
- `public`：公网推荐值。仅限制由公开请求控制的不可信拉取目标，例如 `/sub?url=...`、`/sub?config=...`、`/getruleset?url=...`、公开外部配置里的远程 import/fetch。项目自带本地模板、部署者配置的默认模板和本地 base 文件继续可用。
- `strict`：在 `public` 的拉取限制基础上，始终禁用公开请求触发的 Gist 上传。

## 公网模式不会阻止什么

`public` 不会阻止项目读取自带的 `base/` 模板、部署者在配置文件里指定的本地模板，以及受信任默认配置里的本地资源。限制只挂在“请求方可控”的来源上。

## 上传开关

`lan` 保持旧上传行为。`public` 默认禁用公开请求触发的上传，如确实需要可显式开启：

```ini
[security]
profile=public
allow_public_upload=true
```

也可以使用：

```bash
SUBCONVERTER_ALLOW_PUBLIC_UPLOAD=true
```

`strict` 下即使设置 `allow_public_upload=true` 也不会允许公开上传。

## 推荐迁移步骤

1. 内网自用部署不需要改配置，继续使用默认 `lan`。
2. 对公网暴露的实例，先更新镜像但保持 `lan`，确认业务正常。
3. 将公网实例切到 `public`，观察日志里是否有被阻止的私有地址访问。
4. 如果被阻止的是业务必须访问的内网资源，说明该实例更适合作为内网服务运行；不要直接暴露到公网。
