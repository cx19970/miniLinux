glibc（GNU C 库）：通用标准，桌面 / 服务器 / 嵌入式全场景。

musl libc：轻量高效，容器 / 嵌入式 / 安全优先场景。

uClibc-ng：极致裁剪，深度嵌入式 / 无 MMU 场景。

内核版本匹配原则：
| libc 版本 | 支持内核范围 | 不支持内核 |
| --- | --- | --- |
| glibc 2.2/2.4 | Linux 2.2 ~ 2.6.x | Linux 3.x+（需补丁） |
| glibc 2.12/2.17 | Linux 2.6.32 ~ 5.x | Linux 2.4 及更早 |
| glibc 2.28 | Linux 3.10 ~ 6.x | Linux 2.6 及更早 |
| glibc 2.34+ | Linux 4.19 ~ 7.x | Linux 3.x 及更早 |

兼容性优先版本：C 库选 glibc 2.12/2.17。

功能特性优先版本：C 库选 glibc 2.34。

C库与内核的关系：新内核可以跑旧 libc，旧内核跑不了新 libc，即：libc 依赖内核 syscall 接口实现 C 库功能。

内核、C 库和应用彼此或多或少存在一定的版本依赖，不试图归一到一个版本。
