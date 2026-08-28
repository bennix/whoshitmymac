import type { Metadata } from 'next';
import { Geist, Geist_Mono } from 'next/font/google';
import './globals.css';

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
});

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
});

export const metadata: Metadata = {
  title: 'WhoShitOnMyMac — 看清是谁把硬盘弄脏了',
  description: '安全优先的原生 Mac 清理工具：快照对比、垃圾扫描、应用卸载，默认只进废纸篓。',
  openGraph: {
    title: 'WhoShitOnMyMac — 看清是谁把硬盘弄脏了',
    description: '安全优先的原生 Mac 清理工具：快照对比、垃圾扫描、应用卸载。',
    type: 'website',
    images: [
      {
        url: 'https://raw.githubusercontent.com/bennix/whoshitmymac/main/site/public/og.png',
        width: 1200,
        height: 630,
        alt: 'WhoShitOnMyMac — 看清是谁把硬盘弄脏了',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'WhoShitOnMyMac — 看清是谁把硬盘弄脏了',
    description: '安全优先的原生 Mac 清理工具：快照对比、垃圾扫描、应用卸载。',
    images: ['https://raw.githubusercontent.com/bennix/whoshitmymac/main/site/public/og.png'],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN" className="dark">
      <body className={`${geistSans.variable} ${geistMono.variable} antialiased`}>{children}</body>
    </html>
  );
}
