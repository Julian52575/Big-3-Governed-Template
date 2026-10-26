const app = require("./app");
const db = require("./db");

const PORT = Number(process.env.PORT) || 3000;

const server = app.listen(PORT, () => console.log(`backend listening on :${PORT}`));

async function shutdown() {
  server.close();
  await db.$disconnect();
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
