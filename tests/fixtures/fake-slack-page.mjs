// Fake Slack page for slack-draft tests. It runs a page script (the text of
// an expression, as `agent-tab eval` sends it) against a tiny fake DOM and
// prints the value like agent-tab does. State lives in files, so later calls
// see earlier clicks.
//   DRAFTS_JSON   file: [{"to": "...", "body": "..."}]
//   FAKE_CONFIRM  set: a delete click opens a confirm modal; the row goes
//                 only after the modal is clicked
//   FAKE_NO_DELETE_BUTTON  set: rows have no delete button
//   INPUT_STATE   file: "1" when the main composer file input exists
//   FAKE_INPUT_AFTER_CLICK  set: the input appears only after the attach click
// FAKE_STUCK_MODAL: a delete click hides the row but the dialog stays open.
// FAKE_OLD_DELETE_DIALOG: a "Delete message?" dialog is open before the click.
// FAKE_DECOY: another modal (with its own confirm button) is open too;
// its click writes the file DECOY_HIT.
// Selectors are told apart by marker: dialog, _delete, _to, _body,
// type=file, attach, else a draft row.
// Usage: node fake-slack-page.mjs '<script>'
import fs from "node:fs";
import vm from "node:vm";

const file = process.env.DRAFTS_JSON;
const load = () => (file ? JSON.parse(fs.readFileSync(file, "utf8")) : []);
const save = (rows) => file && fs.writeFileSync(file, JSON.stringify(rows));
let pending = null;
let openDialog = null;  // the delete dialog opened by a click (one object, so identity is stable)
// FAKE_OLD_DELETE_DIALOG: a "Delete message?" dialog open before any click.
const oldDialog = process.env.FAKE_OLD_DELETE_DIALOG
  ? { innerText: "Delete message?", querySelector: () => el("", () => fs.writeFileSync(process.env.DECOY_HIT, "1")) }
  : null;

const el = (text, onClick) => ({ innerText: text, click: onClick || (() => {}) });
// Deletes by POSITION in the list at query time, like a virtualized list: a
// script that reuses a stale row removes the wrong draft.
const rowEl = (r, i) => ({
  innerText: `To: ${r.to}\n${r.body}`,
  querySelector(sel) {
    if (sel.includes("_delete")) {
      if (process.env.FAKE_NO_DELETE_BUTTON) return null;
      return el("", () => {
        if (process.env.FAKE_STUCK_MODAL) {
          // The row hides, but the dialog never closes.
          const cur = load(); cur.splice(i, 1); save(cur);
          openDialog = { innerText: "Delete draft?", querySelector: () => el("", () => {}) };
          return;
        }
        if (process.env.FAKE_CONFIRM) {
          pending = i;
          openDialog = { innerText: "Delete draft?", querySelector: () => el("", () => {
            const cur = load(); cur.splice(pending, 1); save(cur); pending = null; openDialog = null;
          }) };
          return;
        }
        const cur = load(); cur.splice(i, 1); save(cur);
      });
    }
    if (sel.includes("_to")) return r.to === undefined ? null : el(r.to);
    if (sel.includes("_body")) return r.body === undefined ? null : el(r.body);
    return null;
  },
});

const document = {
  querySelectorAll(sel) {
    if (sel.includes("dialog")) {
      // Another modal first (FAKE_DECOY), then the delete dialog while pending.
      const out = [];
      if (process.env.FAKE_DECOY) {
        out.push({ innerText: "Leave channel?", querySelector: () => el("", () => fs.writeFileSync(process.env.DECOY_HIT, "1")) });
      }
      if (oldDialog) out.push(oldDialog);
      if (openDialog) out.push(openDialog);
      return out;
    }
    return load().map(rowEl);
  },
  querySelector(sel) {
    const state = () => fs.existsSync(process.env.INPUT_STATE || "") && fs.readFileSync(process.env.INPUT_STATE, "utf8").trim() === "1";
    if (sel.includes("type=file")) return state() ? el("") : null;
    if (sel.includes("attach")) {
      return el("", () => { if (process.env.FAKE_INPUT_AFTER_CLICK) fs.writeFileSync(process.env.INPUT_STATE, "1"); });
    }
    return null;
  },
};

const value = await vm.runInNewContext(process.argv[2], { document, setTimeout, Promise, JSON, String, RegExp });
console.log(typeof value === "string" ? value : JSON.stringify(value));
