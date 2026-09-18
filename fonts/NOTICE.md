# 字体包（Rock阅读 按需下载）

两款字体都是**开源字体（SIL OFL 1.1）的 GB2312 子集**；按 OFL 的
Reserved Font Name 规则**已改名**，归属声明写在字体文件内部的 copyright 字段里。

| 文件 | 字体族 | 来源（原字体） | 体积 |
|---|---|---|---|
| `RockReaderKai.ttf` | RockReader Kai | 霞鹜文楷 Lite · https://github.com/lxgw/LxgwWenKai-Lite | 3.27 MB |
| `RockReaderSong.ttf` | RockReader Song | Noto Serif SC（思源宋体同源）· https://fonts.google.com/noto/specimen/Noto+Serif+SC | 2.91 MB |

## 为什么做成子集

原字体 13.3MB / 24MB，国内网络下一次下载太慢。子集化后**楷体 3.27MB、宋体 2.91MB**，
覆盖 **GB2312 全部 6763 字**（日常中文书籍与绝大多数人名都够用）；
极罕见的字会回退系统字体显示（只影响那一两个字的字型，不影响阅读）。

## 怎么复现（可审计）

```bash
# 1) 宋体是变量字体 → 先定字重
python -m fontTools.varLib.instancer NotoSerifSC-VF.ttf wght=400 -o song-pinned.ttf
# 2) 子集化（字符集 = GB2312 全集 6763 字 + ASCII + 常用标点 + 全角符号）
pyftsubset <原始字体>.ttf --unicodes-file=gb2312.txt --no-hinting --desubroutinize -o out.ttf
# 3) 改名（OFL 要求：修改后的衍生版本不得使用原 Reserved Font Name）
```

## 下载源（应用内按顺序尝试，三个源都校验 SHA256）

1. jsDelivr CDN（国内可达的官方 CDN）：`https://cdn.jsdelivr.net/gh/Rocktier/Rock-Reader@fonts-v1/fonts/<file>`
2. GitHub Release 附件
3. GitHub raw
