import assert from "node:assert/strict";
import test from "node:test";

import { shouldQueueOscPolicy } from "../src/oscClient.js";

test("offline safety messages drop while slider and TTL queues remain enabled", () => {
  assert.equal(shouldQueueOscPolicy("safety"), false);
  assert.equal(shouldQueueOscPolicy("never"), false);
  assert.equal(shouldQueueOscPolicy("latest"), true);
  assert.equal(shouldQueueOscPolicy("ttl"), true);
});
