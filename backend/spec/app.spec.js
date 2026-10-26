const request = require("supertest");

jest.mock("../src/db", () => ({
  item: { findMany: jest.fn(), create: jest.fn() },
}));

const db = require("../src/db");
const app = require("../src/app");

describe("backend", () => {
  test("GET /health", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: "ok" });
  });

  test("GET /items lists items", async () => {
    db.item.findMany.mockResolvedValue([{ id: "1", name: "first" }]);
    const res = await request(app).get("/items");
    expect(res.status).toBe(200);
    expect(res.body).toEqual([{ id: "1", name: "first" }]);
  });

  test("POST /items creates an item", async () => {
    db.item.create.mockImplementation(({ data }) => ({ id: "2", ...data }));
    const res = await request(app).post("/items").send({ name: "second" });
    expect(res.status).toBe(201);
    expect(res.body).toEqual({ id: "2", name: "second" });
  });

  test("POST /items rejects an empty name", async () => {
    const res = await request(app).post("/items").send({ name: " " });
    expect(res.status).toBe(400);
    expect(db.item.create).not.toHaveBeenCalledWith({ data: { name: " " } });
  });
});
