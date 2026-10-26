const express = require("express");
const { z } = require("zod");
const db = require("./db");

const itemSchema = z.object({ name: z.string().trim().min(1).max(200) });

const app = express();
app.use(express.json());

// Traefik strips the /api prefix, so routes are mounted at the root.
app.get("/health", (_req, res) => res.json({ status: "ok" }));

app.get("/items", async (_req, res) => {
  res.json(await db.item.findMany({ orderBy: { createdAt: "asc" } }));
});

app.post("/items", async (req, res) => {
  const parsed = itemSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: z.treeifyError(parsed.error) });
  }
  res.status(201).json(await db.item.create({ data: parsed.data }));
});

module.exports = app;
