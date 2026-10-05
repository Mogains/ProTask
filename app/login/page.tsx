import { redirect } from "next/navigation";
import { AuthForm } from "@/components/AuthForm";
import { isSetUp } from "@/lib/auth";
import { loginAction } from "../auth-actions";

export const dynamic = "force-dynamic";

export default async function LoginPage() {
  if (!(await isSetUp())) redirect("/setup");
  return <AuthForm mode="login" action={loginAction} />;
}
