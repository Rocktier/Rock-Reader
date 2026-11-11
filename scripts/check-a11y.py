#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
无障碍静态闸门：找出「能点、但读屏念不出名字」的控件。

## 判据

把源码切成一个个**组件构建表达式**（见下），表达式里只要出现 `.onClick(`
就是可点控件。该表达式必须至少具备下列之一，否则 FAIL：

  1. 有可念的文字：`Text('返回')` / `Button('取消')` / `Span('x')`
     —— 文字本身就是名字。**纯符号不算**：`Text('←')` 读屏念「左箭头」。
  2. `.accessibilityText(...)` —— 显式起名
  3. `.accessibilityTextHint(...)` / `.accessibilityGroup(true)`
  4. `.accessibilityLevel('no')` —— 明确声明与读屏无关（遮罩、背景点击）

## 为什么用「括号深度」切表达式，而不是「逐行找 . 续行」

ArkUI 里同一个组件的写法千变万化：

    Row() { Text('x') }.onClick(A)            ← 单行
    Row() {                                   ← 子块
      Text('x')
    }
    .width('100%')
    .border({ width: { left: 3 } })           ← 多行对象属性
    .onClick(B)                               ← 中间还夹注释

早先「组件行开链 + 后续 `.` 续行」的切法，遇到 `}` 之后接属性就开不了新链，
于是那批 onClick **既不 FAIL 也不 PASS —— 静默漏检**。
换成括号深度后：一个表达式从 `Row()` 起，到 depth 回 0 且下一行不再以 `.` 续接为止，
上面三种写法都落在同一个区间里。

## 用法

    python scripts/check-a11y.py            # 扫本仓，退出码 0 = 全过
    python scripts/check-a11y.py --selftest # 只跑内联正反例，验闸门自己
"""

import re
import sys
import glob
import os

# 组件构建行的开头：大写开头的标识符（ArkUI 组件一律大写开头）
BUILD_RE = re.compile(r'^\s*[A-Z][A-Za-z0-9_]*\s*[({]')
# 合格替代证据
OK_MARKERS = (
    'accessibilityText(',
    'accessibilityTextHint(',
    'accessibilityGroup(true',
    "accessibilityLevel('no')",
    'accessibilityLevel("no")',
)
# 「有内容可念」：至少一个字母 / 数字 / 汉字。纯符号（← × ⋯ ✓ ›）不算。
READABLE_RE = re.compile(r'[0-9A-Za-z\u4e00-\u9fa5]')
TEXTY_RE = re.compile(r'(?:Text|Button|Span)\(\s*([^\n]*)')


def _strip_literals(s):
    """抹掉字符串内容再数括号 —— `Text('(')` 里的括号不该记账。"""
    s = re.sub(r"'[^'\n]*'", "''", s)
    s = re.sub(r'"[^"\n]*"', '""', s)
    s = re.sub(r'`[^`\n]*`', '``', s)
    return s


def _delta(s):
    s = _strip_literals(s)
    return (s.count('(') + s.count('{') + s.count('[')
            - s.count(')') - s.count('}') - s.count(']'))


def _is_comment_or_blank(s):
    s = s.strip()
    return (not s) or s.startswith(('//', '*', '/*', '*/'))


def _next_sig(lines, i):
    """第 i 行（0-based）之后第一条非空、非注释行的内容。"""
    j = i + 1
    while j < len(lines) and _is_comment_or_blank(lines[j]):
        j += 1
    return lines[j].strip() if j < len(lines) else ''


def split_expressions(lines):
    """把源码切成组件构建表达式，返回 [(起始行号 1-based, 表达式文本)]。

    起点：depth 为 0 时遇到 `BigName(` / `BigName{`
    终点：depth 回到 0，且**下一条有效行不再以 `.` 开头**（还有链式续接就接着算）

    ⚠️ 判「下一条有效行」必须跳过空行与注释：属性链中间夹注释是常见写法，
       拿 `// 当前章 = …` 当终止信号会让表达式提前结束，后面的 onClick 直接丢失。
    """
    exprs = []
    cur_start = None
    cur = []
    depth = 0

    for i, line in enumerate(lines, start=1):
        s = line.strip()
        if cur_start is None:
            if depth == 0 and BUILD_RE.match(line):
                cur_start = i
                cur = [line]
                depth = _delta(line)
                if depth == 0 and not _next_sig(lines, i - 1).startswith('.'):
                    exprs.append((cur_start, '\n'.join(cur)))
                    cur_start, cur, depth = None, [], 0
            continue

        cur.append(line)
        depth += _delta(line)
        if depth <= 0 and not _next_sig(lines, i - 1).startswith('.'):
            exprs.append((cur_start, '\n'.join(cur)))
            cur_start, cur, depth = None, [], 0

    if cur_start is not None:
        exprs.append((cur_start, '\n'.join(cur)))
    return exprs


def has_readable_text(block_text):
    for m in TEXTY_RE.finditer(block_text):
        for s in re.findall(r"'([^']*)'", m.group(1)):
            if READABLE_RE.search(s):
                return True
    return False


def check_source(text):
    """返回 [(行号, 首行摘要)] —— 缺名字的可点控件。"""
    lines = text.splitlines()
    bad = []
    for start, expr in split_expressions(lines):
        if '.onClick(' not in expr:
            continue
        if has_readable_text(expr):
            continue
        if any(m in expr for m in OK_MARKERS):
            continue
        bad.append((start, lines[start - 1].strip()[:70]))
    return bad


def count_clicks(text):
    lines = text.splitlines()
    n = 0
    for line in lines:
        s = line.strip()
        if '.onClick(' in s and not s.startswith(('//', '*', '/*')):
            n += 1
    return n


SELFTEST = [
    # (说明, 源码, 期望 FAIL 数)
    ('有文字的按钮 => 过', "Button('保存')\n  .onClick(() => {})", 0),
    ('纯符号文字 => 漏', "Text('←')\n  .onClick(() => {})", 1),
    ('图标按钮无名 => 漏', "Image($r('app.media.ic'))\n  .onClick(() => {})", 1),
    ('图标按钮起名 => 过', "Image($r('app.media.ic'))\n  .accessibilityText('返回')\n  .onClick(() => {})", 0),
    ('明确无关 => 过', "Column()\n  .accessibilityLevel('no')\n  .onClick(() => {})", 0),
    # 关键回归：子块闭合后接属性 —— 旧切链法在这里静默漏检
    ('子块后接 onClick，子有文字 => 过',
     "Row() {\n  Text('返回')\n}\n.width('100%')\n.onClick(() => {})", 0),
    ('子块后接 onClick，子无文字 => 漏',
     "Row() {\n  Image($r('a'))\n}\n.width('100%')\n.onClick(() => {})", 1),
    ('多行对象属性 + 注释夹在中间 => 不漏',
     "Row() {\n  Image($r('a'))\n}\n// 说明\n.border({\n  width: { left: 3 }\n})\n.onClick(() => {})", 1),
    ('子块里有名字，父层 onClick => 过',
     "Column() {\n  Row() {\n    Text('标题')\n  }\n  .onClick(() => {})\n}", 0),
]


def selftest():
    ok = True
    for desc, src, want in SELFTEST:
        got = len(check_source(src))
        flag = '✓' if got == want else '✗'
        if got != want:
            ok = False
        print(f'{flag} {desc}  (期望 {want}，实际 {got})')
    print('\nSELFTEST ' + ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


def main():
    if '--selftest' in sys.argv:
        return selftest()

    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                        'entry', 'src', 'main', 'ets')
    files = sorted(glob.glob(os.path.join(root, 'pages', '**', '*.ets'), recursive=True) +
                   glob.glob(os.path.join(root, 'view', '**', '*.ets'), recursive=True) +
                   glob.glob(os.path.join(root, 'components', '**', '*.ets'), recursive=True))
    if not files:
        print('没找到 .ets 源码，检查路径')
        return 1

    total = 0
    clicks = 0
    for p in files:
        with open(p, encoding='utf-8') as f:
            text = f.read()
        clicks += count_clicks(text)
        bad = check_source(text)
        if bad:
            total += len(bad)
            print(f'\n✗ {os.path.relpath(p, root)}')
            for ln, head in bad:
                print(f'    L{ln}  可点但没有名字：{head}')

    print(f'\n扫描 {len(files)} 个文件，{clicks} 处 onClick，'
          f'{total} 处缺无障碍名字')
    if total:
        print('FAIL —— 补 accessibilityText(...)，或确认与读屏无关后标 accessibilityLevel(\'no\')')
        return 1
    print('PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
