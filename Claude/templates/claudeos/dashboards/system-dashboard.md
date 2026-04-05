# ClaudeOS System Dashboard

## 🧭 Global Status

- Mode: Auto
- Project: {{name}}
- Phase: {{Design/Dev/Verify}}

---

## ⏱ Time Control

- Start Time: {{timestamp}}
- Elapsed: {{time}}
- Remaining: {{time}}
- Limit: 5h

Status:
- OK / WARNING / STOP

---

## 🔁 Loop Status

- Current Loop: {{Monitor/Dev/Verify/Improve}}
- Loop Progress: {{%}}

---

## ✅ STABLE Status

- Current Success: {{n}}
- Required: {{N}}
- STABLE: {{yes/no}}

---

## ⚙ CI Status

- Last Result: {{success/fail}}
- Retry Count: {{n}} / 15
- Auto Repair: {{active}}

---

## 🚨 Risk Status

- Loop Risk: {{low/medium/high}}
- CI Risk: {{low/medium/high}}
- Security Risk: {{low/medium/high}}

---

## 👥 Agent Status

- CTO: {{active}}
- Architect: {{active}}
- DevAPI: {{active}}
- DevUI: {{active}}
- QA: {{active}}
- Security: {{active}}
- Ops: {{active}}

---

## 📊 Project Status

- Current: {{status}}
- Issues: {{n}}
- Blocked: {{n}}

---

## 🛑 Stop Conditions

- 5h reached: {{yes/no}}
- Retry limit: {{yes/no}}
- Blocked: {{yes/no}}

---

## 🎯 Next Action

{{next_action}}