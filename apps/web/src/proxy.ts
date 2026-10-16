import { NextResponse, type NextRequest } from "next/server";
export function proxy(request: NextRequest) {
  if ((request.nextUrl.pathname.startsWith("/app") || request.nextUrl.pathname === "/onboarding") && !request.cookies.has("omniassist_session")) return NextResponse.redirect(new URL("/signin", request.url));
  if ((request.nextUrl.pathname === "/signin" || request.nextUrl.pathname === "/signup") && request.cookies.has("omniassist_session")) return NextResponse.redirect(new URL("/app/today", request.url));
  return NextResponse.next();
}
export const config = { matcher: ["/app/:path*", "/onboarding", "/signin", "/signup"] };
