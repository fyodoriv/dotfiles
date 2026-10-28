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
// Selectors are told apart by marker: _delete, _to, _body, confirm,
// type=file, attach, else a draft row.
// Usage: node fake-slack-page.mjs '<script>'
import fs from "node:fs";
import vm from "node:vm";

const file = process.env.DRAFTS_JSON;
const load = () => (file ? JSON.parse(fs.readFileSync(file, "utf8")) : []);
const save = (rows) => file && fs.writeFileSync(file, JSON.stringify(rows));
let pending = null;

const el = (text, onClick) => ({ innerText: text, click: onClick || (() => {}) });
const rowEl = (r) => ({
  innerText: `To: ${r.to}\n${r.body}`,
  querySelector(sel) {
    if (sel.includes("_delete")) {
      if (process.env.FAKE_NO_DELETE_BUTTON) return null;
      return el("", () => {
        if (process.env.FAKE_CONFIRM) { pending = r; return; }
        save(load().filter((x) => !(x.to === r.to && x.body === r.body)));
      });
    }
    if (sel.includes("_to")) return r.to === undefined ? null : el(r.to);
    if (sel.includes("_body")) return r.body === undefined ? null : el(r.body);
    return null;
  },
});

const document = {
  querySelectorAll() { return load().map(rowEl); },
  querySelector(sel) {
    if (sel.includes("confirm")) {
      return pending ? el("", () => {
        save(load().filter((x) => !(x.to === pending.to && x.body === pending.body)));
        pending = null;
      }) : null;
    }
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
