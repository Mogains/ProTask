import { redirect } from "next/navigation";
import { AuthForm } from "@/components/AuthForm";
import { isSetUp, MIN_PASSWORD_LENGTH } from "@/lib/auth";
import { setupAction } from "../auth-actions";

export const dynamic = "force-dynamic";

export default async function SetupPage() {
  if (await isSetUp()) redirect("/login");
  return <AuthForm mode="setup" action={setupAction} minLength={MIN_PASSWORD_LENGTH} />;
}
