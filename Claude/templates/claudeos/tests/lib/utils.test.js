import assert from "node:assert/strict";
import { normalizePath, toList } from "../../scripts/lib/utils.js";

assert.equal(normalizePath("a\\b"), "a/b");
assert.deepEqual(toList("x"), ["x"]);
