import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = { title: "Clocktower Live", description: "시계탑 실시간 진행 보조 앱" };
export default function RootLayout({children}:{children:React.ReactNode}) { return <html lang="ko"><body>{children}</body></html>; }
