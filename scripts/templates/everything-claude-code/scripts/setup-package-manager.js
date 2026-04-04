import { detectPackageManager } from "./lib/package-manager.js";

const detected = detectPackageManager(process.argv.slice(2));
console.log(`推奨パッケージマネージャ: ${detected}`);
