/**
 * 纯逻辑单测运行器
 *
 * 为什么这么绕：引擎源码是 .ets（ArkTS），但里面**不含任何 ArkUI/Node 专属语法**，
 * 所以可以用 esbuild 把 .ets 当 TS 编译，在 Node 里直接测。
 * 这样"算法正确性"不必等真机 —— CI 无模拟器，这是唯一能自动化的验证手段（见 docs/v1-design.md §9）。
 */
import { build } from 'esbuild';
import { execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const outfile = join(mkdtempSync(join(tmpdir(), 'rockreader-test-')), 'tests.mjs');

await build({
  entryPoints: ['test/all.test.ts'],
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node18',
  outfile,
  loader: { '.ets': 'ts' },
  // 引擎源码内部是无扩展名导入（ArkTS 写法，如 './PageTableBuilder'）；
  // 必须显式把 .ets 放进解析顺序，否则 esbuild 只找 .ts/.js → Could not resolve。
  resolveExtensions: ['.ets', '.ts', '.mjs', '.js', '.json'],
  logLevel: 'warning'
});

execFileSync(process.execPath, ['--test', outfile], { stdio: 'inherit' });
