import { useEffect, useState } from "react";

type Status = "checking" | "ok" | "unreachable";

export default function App() {
  const [status, setStatus] = useState<Status>("checking");

  useEffect(() => {
    fetch("/api/health")
      .then((res) => setStatus(res.ok ? "ok" : "unreachable"))
      .catch(() => setStatus("unreachable"));
  }, []);

  return (
    <main>
      <h1>Big 3 Template</h1>
      <p>
        React + Vite frontend. Edit <code>frontend/src/App.tsx</code> and save to reload.
      </p>
      <p>
        Backend: <strong>{status}</strong>
      </p>
    </main>
  );
}
