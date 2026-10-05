import App from "@/components/App";
import { getSnapshot } from "@/lib/state";

export const dynamic = "force-dynamic";

export default async function Page() {
  return <App initial={await getSnapshot()} />;
}
