import type { Metadata } from "next";
import { ui } from "./fonts";
import "./globals.css";

export const metadata: Metadata = {
  title: "RPG Game",
  description: "Game nhập vai: leo Tháp Vực Thẳm, khám phá, săn đồ.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="vi" className="h-full antialiased">
      <body className={`${ui.className} min-h-full flex flex-col`}>{children}</body>
    </html>
  );
}
