'use client';

import {
  ArrowDownToLine,
  Code2,
  ExternalLink,
  FolderSearch,
  History,
  ScanSearch,
  ShieldCheck,
  Trash2,
} from 'lucide-react';

const downloadUrl =
  'https://github.com/bennix/whoshitmymac/releases/download/v1.0.0/WhoShitOnMyMac-1.0.0.dmg';

const features = [
  {
    icon: FolderSearch,
    eyebrow: 'Directory scan',
    title: '看见空间从哪里消失',
    copy: '按文件和文件夹的实际占用排序，汇总疑似垃圾数量与预计可清理容量，让空间去向一目了然。',
  },
  {
    icon: ScanSearch,
    eyebrow: 'Junk scan',
    title: '只清理能解释的内容',
    copy: '按缓存、日志、安装包、开发产物等类别扫描；无法证明安全的目标会被跳过。',
  },
  {
    icon: Trash2,
    eyebrow: 'App uninstall',
    title: '卸载应用，也找到残留',
    copy: '预览应用本体与关联残留，识别共享文件和正在运行的应用，再决定哪些进入废纸篓。',
  },
];

const safetyItems = [
  { icon: ShieldCheck, label: '黑名单与白名单双重保护' },
  { icon: Trash2, label: '默认移动到废纸篓，可恢复' },
  { icon: History, label: '操作历史留痕，便于复核' },
];

export default function Home() {
  return (
    <main className="min-h-screen overflow-hidden bg-background text-foreground">
      <div className="pointer-events-none fixed inset-x-0 top-0 h-[520px] bg-[radial-gradient(circle_at_70%_8%,rgba(37,238,205,0.16),transparent_34%),radial-gradient(circle_at_22%_18%,rgba(41,123,255,0.2),transparent_38%)]" />

      <header className="relative z-10 mx-auto flex w-full max-w-6xl items-center justify-between px-5 py-6 sm:px-8">
        <a href="#top" className="flex items-center gap-3" aria-label="WhoShitOnMyMac 首页">
          <img src="/app-icon.png" alt="" className="h-10 w-10" />
          <span className="text-sm font-semibold tracking-[-0.02em] sm:text-base">WhoShitOnMyMac</span>
        </a>
        <a
          href="https://github.com/bennix/whoshitmymac"
          className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.045] px-4 py-2 text-sm text-slate-200 transition hover:border-cyan-300/35 hover:bg-white/[0.075]"
        >
          <Code2 className="h-4 w-4" aria-hidden="true" />
          GitHub
        </a>
      </header>

      <section id="top" className="relative mx-auto grid min-h-[680px] w-full max-w-6xl items-center gap-12 px-5 pb-20 pt-12 sm:px-8 lg:grid-cols-[1.08fr_0.92fr] lg:pt-8">
        <div className="max-w-2xl">
          <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-cyan-200/15 bg-cyan-200/[0.055] px-3 py-1.5 text-xs font-medium text-cyan-100">
            <ShieldCheck className="h-3.5 w-3.5" aria-hidden="true" />
            Developer ID 签名 · Apple 公证
          </div>
          <h1 className="text-balance text-[clamp(3.2rem,8vw,6.7rem)] font-semibold leading-[0.91] tracking-[-0.075em] text-white">
            看清是谁把硬盘
            <span className="block bg-gradient-to-r from-cyan-300 via-emerald-300 to-amber-300 bg-clip-text text-transparent">弄脏了。</span>
          </h1>
          <p className="mt-7 max-w-xl text-pretty text-lg leading-8 text-slate-300 sm:text-xl">
            一款安全优先的原生 Mac 清理工具。目录扫描、垃圾扫描、应用卸载，所有删除先预览，默认只进废纸篓。
          </p>
          <div className="mt-9 flex flex-col gap-3 sm:flex-row">
            <a
              href={downloadUrl}
              className="inline-flex min-h-12 items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-cyan-300 to-emerald-300 px-6 py-3 text-sm font-bold text-slate-950 shadow-[0_18px_50px_rgba(35,230,190,0.22)] transition hover:-translate-y-0.5 hover:brightness-105"
            >
              <ArrowDownToLine className="h-4 w-4" aria-hidden="true" />
              下载 macOS 版
            </a>
            <a
              href="#features"
              className="inline-flex min-h-12 items-center justify-center gap-2 rounded-xl border border-white/12 bg-white/[0.045] px-6 py-3 text-sm font-semibold text-white transition hover:bg-white/[0.075]"
            >
              查看功能
              <ExternalLink className="h-4 w-4" aria-hidden="true" />
            </a>
          </div>
          <p className="mt-4 text-xs text-slate-500">v1.0.0 · macOS 14 Sonoma 或更高版本 · Apple Silicon / Intel</p>
        </div>

        <div className="relative mx-auto w-full max-w-[500px] lg:justify-self-end">
          <div className="absolute inset-10 rounded-full bg-cyan-300/20 blur-[80px]" />
          <div className="relative rounded-[38px] border border-white/10 bg-gradient-to-b from-white/[0.09] to-white/[0.025] p-7 shadow-[0_35px_120px_rgba(0,0,0,0.52)] backdrop-blur-xl sm:p-10">
            <img
              src="/app-icon.png"
              alt="WhoShitOnMyMac 应用图标"
              className="mx-auto aspect-square w-full max-w-[340px] drop-shadow-[0_30px_45px_rgba(0,0,0,0.45)]"
            />
            <div className="mt-6 grid grid-cols-3 gap-2 text-center text-[11px] font-medium text-slate-300 sm:text-xs">
              <span className="rounded-lg border border-white/8 bg-black/15 px-2 py-2.5">扫描</span>
              <span className="rounded-lg border border-white/8 bg-black/15 px-2 py-2.5">清理</span>
              <span className="rounded-lg border border-white/8 bg-black/15 px-2 py-2.5">卸载</span>
            </div>
          </div>
        </div>
      </section>

      <section id="features" className="relative border-y border-white/[0.07] bg-white/[0.025] py-24">
        <div className="mx-auto w-full max-w-6xl px-5 sm:px-8">
          <div className="max-w-2xl">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-300">Three clear answers</p>
            <h2 className="mt-4 text-4xl font-semibold tracking-[-0.045em] text-white sm:text-5xl">少一点猜测，多一点证据。</h2>
          </div>
          <div className="mt-12 grid gap-4 lg:grid-cols-3">
            {features.map(({ icon: Icon, eyebrow, title, copy }) => (
              <article key={title} className="rounded-3xl border border-white/[0.08] bg-slate-950/45 p-7">
                <div className="flex h-11 w-11 items-center justify-center rounded-2xl border border-cyan-200/15 bg-cyan-200/[0.07] text-cyan-200">
                  <Icon className="h-5 w-5" aria-hidden="true" />
                </div>
                <p className="mt-7 text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-500">{eyebrow}</p>
                <h3 className="mt-2 text-xl font-semibold tracking-[-0.025em] text-white">{title}</h3>
                <p className="mt-3 text-sm leading-7 text-slate-400">{copy}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="relative mx-auto grid w-full max-w-6xl gap-12 px-5 py-24 sm:px-8 lg:grid-cols-2 lg:items-center">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-amber-300">Safety by default</p>
          <h2 className="mt-4 text-4xl font-semibold tracking-[-0.045em] text-white sm:text-5xl">清理工具首先要懂得克制。</h2>
          <p className="mt-5 max-w-xl text-base leading-8 text-slate-400">
            系统路径与共享数据有硬保护；白名单可以继续扩大保护边界；不确定、占用中或最近活跃的内容不会被偷偷选中。
          </p>
        </div>
        <div className="grid gap-3">
          {safetyItems.map(({ icon: Icon, label }) => (
            <div key={label} className="flex items-center gap-4 rounded-2xl border border-white/[0.08] bg-white/[0.035] p-5">
              <Icon className="h-5 w-5 text-emerald-300" aria-hidden="true" />
              <span className="text-sm font-medium text-slate-200">{label}</span>
            </div>
          ))}
        </div>
      </section>

      <footer className="border-t border-white/[0.07] px-5 py-8 text-center text-xs text-slate-500 sm:px-8">
        WhoShitOnMyMac · Built for macOS · Source and releases on GitHub
      </footer>
    </main>
  );
}
