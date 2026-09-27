import "./globals.css";
import type { Metadata } from "next";
export const metadata:Metadata={title:"QuoteAI — CBDEVS",description:"Professional quote management by CBDEVS."};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>}