<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0" />
  <title>🏠 Yoshino Point</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Hiragino Kuma Gothic ProN', 'Noto Sans JP', 'Hiragino Sans', sans-serif;
      background: linear-gradient(135deg, #FFF9F0 0%, #FFF0F5 50%, #F0F5FF 100%);
      min-height: 100vh;
    }
    #app { max-width: 480px; margin: 0 auto; position: relative; min-height: 100vh; }
    button { font-family: inherit; }
    button:active { transform: scale(0.97) !important; }
    @keyframes fadeIn {
      from { opacity: 0; transform: translateX(-50%) translateY(-10px); }
      to   { opacity: 1; transform: translateX(-50%) translateY(0); }
    }
    .loading {
      display: flex; align-items: center; justify-content: center;
      min-height: 100vh; font-size: 16px; color: #aaa; flex-direction: column; gap: 12px;
    }
  </style>
</head>
<body>
<div id="app"><div class="loading"><div style="font-size:40px">🏠</div><div>読み込み中...</div></div></div>

<script src="https://cdnjs.cloudflare.com/ajax/libs/react/18.2.0/umd/react.production.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/react-dom/18.2.0/umd/react-dom.production.min.js"></script>
<script type="module">
import { initializeApp } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-app.js";
import { getDatabase, ref, onValue, set, update } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-database.js";

const firebaseConfig = {
  apiKey: "AIzaSyDNZq9mMqy_OkDj0E7TljqQFAJE3K7KMgc",
  authDomain: "yoshino-point.firebaseapp.com",
  databaseURL: "https://yoshino-point-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "yoshino-point",
  storageBucket: "yoshino-point.firebasestorage.app",
  messagingSenderId: "662011428968",
  appId: "1:662011428968:web:fc319e61ea34603fd77bdd"
};

const firebaseApp = initializeApp(firebaseConfig);
const db = getDatabase(firebaseApp);

const { useState, useEffect, useRef } = React;

const CHORES = [
  { id: 1,  name: "料理",               icon: "🍳", points: 30 },
  { id: 2,  name: "食事の準備",         icon: "🥢", points: 5  },
  { id: 3,  name: "皿洗い",             icon: "🍽️", points: 15 },
  { id: 4,  name: "食器を戻す",         icon: "🥣", points: 5  },
  { id: 5,  name: "お茶をつくる",       icon: "🍵", points: 5  },
  { id: 6,  name: "ゴミ捨て&袋交換",   icon: "🗑️", points: 15 },
  { id: 7,  name: "テーブル拭き",       icon: "🧽", points: 5  },
  { id: 8,  name: "シャッターを開ける", icon: "🌅", points: 5  },
  { id: 9,  name: "シャッターを閉める", icon: "🌙", points: 5  },
  { id: 10, name: "掃除機をかける",     icon: "🧹", points: 20 },
  { id: 20, name: "階段の掃除機",       icon: "🪜", points: 15 },
  { id: 11, name: "洗濯を回す",         icon: "🌀", points: 15 },
  { id: 12, name: "洗濯を干す",         icon: "👕", points: 15 },
  { id: 13, name: "洗濯を畳む",         icon: "📦", points: 15 },
  { id: 14, name: "部屋の掃除",         icon: "🏠", points: 20 },
  { id: 15, name: "トイレ掃除",         icon: "🚽", points: 35 },
  { id: 16, name: "洗面所の掃除",       icon: "🪥", points: 15 },
  { id: 17, name: "靴をしまう",         icon: "👟", points: 5  },
  { id: 18, name: "玄関掃除",           icon: "🚪", points: 10 },
  { id: 19, name: "お風呂掃除",         icon: "🛁", points: 20 },
];

const MEMBERS = [
  { id: "mama",      name: "ママ",   avatar: "👩", color: "#E87BAA" },
  { id: "papa",      name: "パパ",   avatar: "👨", color: "#4A90D9" },
  { id: "son",       name: "ひろと", avatar: "👦", color: "#50C878" },
  { id: "daughter1", name: "さえ",   avatar: "👧", color: "#FF9F43" },
  { id: "daughter2", name: "にな",   avatar: "🧒", color: "#A29BFE" },
];

const RANKS = [
  { min: 0,   label: "おてつだい見習い", emoji: "🌱" },
  { min: 30,  label: "がんばりや",       emoji: "⭐" },
  { min: 80,  label: "おてつだい上手",   emoji: "🌟" },
  { min: 150, label: "家事マスター",     emoji: "🏆" },
  { min: 250, label: "家族のヒーロー",   emoji: "👑" },
];

function getRank(pts) {
  for (let i = RANKS.length - 1; i >= 0; i--) {
    if (pts >= RANKS[i].min) return RANKS[i];
  }
  return RANKS[0];
}

function getWeekStart(date) {
  const d = new Date(date);
  const day = d.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  d.setDate(d.getDate() + diff);
  d.setHours(0, 0, 0, 0);
  return d;
}

function formatWeekRange(weekStartTs) {
  const start = new Date(weekStartTs);
  const end = new Date(weekStartTs);
  end.setDate(end.getDate() + 6);
  const fmt = d => (d.getMonth() + 1) + "/" + d.getDate();
  return fmt(start) + "（月）〜 " + fmt(end) + "（日）";
}

const DAY_NAMES = ["日", "月", "火", "水", "木", "金", "土"];
function formatDateTime(ts) {
  const d = new Date(ts);
  return d.getFullYear() + "年" + (d.getMonth() + 1) + "月" + d.getDate() + "日（" +
    DAY_NAMES[d.getDay()] + "） " + d.toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" });
}

function App() {
  const now = new Date();
  const thisWeekStart = getWeekStart(now).getTime();

  const [data, setData] = useState(null); // Firebase data
  const [selectedMember, setSelectedMember] = useState(MEMBERS[0].id);
  const [toast, setToast] = useState(null);
  const [tab, setTab] = useState("home");
  const [confirmDelete, setConfirmDelete] = useState(null);
  const toastTimer = useRef(null);

  // Subscribe to Firebase
  useEffect(() => {
    const dbRef = ref(db, "yoshino-point");
    const unsub = onValue(dbRef, snapshot => {
      const val = snapshot.val();
      if (val) {
        setData(val);
        // Check week rollover
        if (val.currentWeekStart && thisWeekStart > val.currentWeekStart) {
          doWeekRollover(val);
        }
      } else {
        // Initialize empty data
        const init = {
          currentWeekStart: thisWeekStart,
          weeklyPoints: Object.fromEntries(MEMBERS.map(m => [m.id, 0])),
          history: {},
          pastWeeks: {},
        };
        set(ref(db, "yoshino-point"), init);
      }
    });
    return () => unsub();
  }, []);

  function doWeekRollover(val) {
    const wp = val.weeklyPoints || {};
    const top3 = [...MEMBERS]
      .sort((a, b) => (wp[b.id] || 0) - (wp[a.id] || 0))
      .slice(0, 3)
      .map(m => ({ name: m.name, avatar: m.avatar, color: m.color, points: wp[m.id] || 0 }));

    const pastWeeks = val.pastWeeks ? Object.values(val.pastWeeks) : [];
    const newPastKey = "week_" + val.currentWeekStart;
    const newPastEntry = {
      weekStartTs: val.currentWeekStart,
      weekLabel: formatWeekRange(val.currentWeekStart),
      top3,
    };

    const newPastWeeks = { ...(val.pastWeeks || {}), [newPastKey]: newPastEntry };
    // Keep only last 10
    const keys = Object.keys(newPastWeeks).sort().reverse().slice(0, 10);
    const trimmed = Object.fromEntries(keys.map(k => [k, newPastWeeks[k]]));

    update(ref(db, "yoshino-point"), {
      currentWeekStart: thisWeekStart,
      weeklyPoints: Object.fromEntries(MEMBERS.map(m => [m.id, 0])),
      history: {},
      pastWeeks: trimmed,
    });
  }

  function showToast(msg, color) {
    if (toastTimer.current) clearTimeout(toastTimer.current);
    setToast({ msg, color });
    toastTimer.current = setTimeout(() => setToast(null), 2000);
  }

  function addPoints(chore) {
    if (!data) return;
    const member = MEMBERS.find(m => m.id === selectedMember);
    const entryId = "e_" + Date.now();
    const entry = {
      id: entryId, memberId: member.id, member: member.name,
      avatar: member.avatar, chore: chore.name, icon: chore.icon,
      points: chore.points, ts: Date.now(),
    };
    const newPts = (data.weeklyPoints?.[selectedMember] || 0) + chore.points;
    update(ref(db, "yoshino-point"), {
      ["weeklyPoints/" + selectedMember]: newPts,
      ["history/" + entryId]: entry,
    });
    showToast(chore.icon + " " + chore.name + " +" + chore.points + "pt！", member.color);
  }

  function deleteEntry(entry) {
    if (!data) return;
    const newPts = Math.max(0, (data.weeklyPoints?.[entry.memberId] || 0) - entry.points);
    update(ref(db, "yoshino-point"), {
      ["weeklyPoints/" + entry.memberId]: newPts,
      ["history/" + entry.id]: null,
    });
    setConfirmDelete(null);
    showToast("↩️ " + entry.chore + " を取り消しました", "#888");
  }

  if (!data) return React.createElement("div", { className: "loading" },
    React.createElement("div", { style: { fontSize: 40 } }, "🏠"),
    React.createElement("div", null, "読み込み中...")
  );

  const wp = data.weeklyPoints || {};
  const historyArr = data.history
    ? Object.values(data.history).sort((a, b) => b.ts - a.ts)
    : [];
  const pastWeeksArr = data.pastWeeks
    ? Object.values(data.pastWeeks).sort((a, b) => b.weekStartTs - a.weekStartTs)
    : [];
  const lastWeek = pastWeeksArr[0] || null;

  const sorted = [...MEMBERS].sort((a, b) => (wp[b.id] || 0) - (wp[a.id] || 0));
  const currentMember = MEMBERS.find(m => m.id === selectedMember);
  const myWeeklyPts = wp[selectedMember] || 0;
  const rank = getRank(myWeeklyPts);
  const nextRank = RANKS.find(r => r.min > myWeeklyPts);
  const pctToNext = nextRank
    ? Math.min(100, ((myWeeklyPts - rank.min) / (nextRank.min - rank.min)) * 100)
    : 100;
  const medalEmoji = i => i === 0 ? "🥇" : i === 1 ? "🥈" : i === 2 ? "🥉" : (i + 1) + "";
  const currentWeekStart = data.currentWeekStart || thisWeekStart;

  return React.createElement("div", { style: { minHeight: "100vh" } },

    // Toast
    toast && React.createElement("div", {
      style: {
        position: "fixed", top: 20, left: "50%", transform: "translateX(-50%)",
        background: toast.color, color: "#fff", borderRadius: 20, padding: "10px 24px",
        fontWeight: 700, fontSize: 15, zIndex: 200, boxShadow: "0 4px 20px rgba(0,0,0,0.15)",
        animation: "fadeIn 0.2s ease", whiteSpace: "nowrap",
      }
    }, toast.msg),

    // Confirm Delete Modal
    confirmDelete && React.createElement("div", {
      onClick: () => setConfirmDelete(null),
      style: { position: "fixed", inset: 0, background: "rgba(0,0,0,0.4)", zIndex: 150, display: "flex", alignItems: "center", justifyContent: "center", padding: 24 }
    },
      React.createElement("div", {
        onClick: e => e.stopPropagation(),
        style: { background: "#fff", borderRadius: 24, padding: "28px 24px", width: "100%", maxWidth: 320, boxShadow: "0 20px 60px rgba(0,0,0,0.2)", textAlign: "center" }
      },
        React.createElement("div", { style: { fontSize: 44, marginBottom: 10 } }, confirmDelete.icon),
        React.createElement("div", { style: { fontSize: 16, fontWeight: 800, color: "#333", marginBottom: 6 } }, "この記録を削除する？"),
        React.createElement("div", { style: { fontSize: 13, color: "#888", marginBottom: 22, lineHeight: 1.7 } },
          confirmDelete.avatar + " " + confirmDelete.member + " — " + confirmDelete.chore,
          React.createElement("br"),
          React.createElement("span", { style: { color: "#FF5A7A", fontWeight: 700 } }, "−" + confirmDelete.points + "pt が取り消されます")
        ),
        React.createElement("div", { style: { display: "flex", gap: 10 } },
          React.createElement("button", {
            onClick: () => setConfirmDelete(null),
            style: { flex: 1, border: "2px solid #eee", borderRadius: 14, padding: "12px 0", fontWeight: 700, fontSize: 14, color: "#999", background: "#fff", cursor: "pointer" }
          }, "キャンセル"),
          React.createElement("button", {
            onClick: () => deleteEntry(confirmDelete),
            style: { flex: 1, border: "none", borderRadius: 14, padding: "12px 0", fontWeight: 700, fontSize: 14, color: "#fff", background: "#FF5A7A", cursor: "pointer" }
          }, "削除する")
        )
      )
    ),

    // Header
    React.createElement("div", { style: { padding: "20px 20px 0", textAlign: "center" } },
      React.createElement("div", { style: { fontSize: 12, color: "#bbb", letterSpacing: 3, textTransform: "uppercase", marginBottom: 4 } }, "家族みんなでがんばろう"),
      React.createElement("div", { style: { fontSize: 26, fontWeight: 900, color: "#333", letterSpacing: -0.5 } }, "🏠 Yoshino Point")
    ),

    // Tab Nav
    React.createElement("div", { style: { display: "flex", margin: "16px 16px 0", background: "#fff", borderRadius: 16, padding: 4, boxShadow: "0 2px 12px rgba(0,0,0,0.06)" } },
      [["home", "🏡 記録"], ["rank", "🏆 ランキング"], ["history", "📋 履歴"]].map(([key, label]) =>
        React.createElement("button", {
          key,
          onClick: () => setTab(key),
          style: {
            flex: 1, border: "none", borderRadius: 12, padding: "8px 0", fontSize: 13, fontWeight: 700,
            cursor: "pointer", transition: "all 0.2s",
            background: tab === key ? "#FF6B9D" : "transparent",
            color: tab === key ? "#fff" : "#999",
          }
        }, label)
      )
    ),

    // Content
    React.createElement("div", { style: { padding: "16px 16px 100px" } },

      // HOME TAB
      tab === "home" && React.createElement(React.Fragment, null,
        React.createElement("div", { style: { marginBottom: 16 } },
          React.createElement("div", { style: { fontSize: 12, color: "#aaa", marginBottom: 8, fontWeight: 600 } }, "だれがやった？"),
          React.createElement("div", { style: { display: "flex", gap: 8 } },
            MEMBERS.map(m =>
              React.createElement("button", {
                key: m.id, onClick: () => setSelectedMember(m.id),
                style: {
                  flex: 1, border: "2px solid", borderColor: selectedMember === m.id ? m.color : "#eee",
                  borderRadius: 14, padding: "8px 4px", background: selectedMember === m.id ? m.color + "22" : "#fff",
                  cursor: "pointer", transition: "all 0.2s", textAlign: "center",
                }
              },
                React.createElement("div", { style: { fontSize: 22 } }, m.avatar),
                React.createElement("div", { style: { fontSize: 11, fontWeight: 700, color: selectedMember === m.id ? m.color : "#999" } }, m.name)
              )
            )
          )
        ),

        React.createElement("div", {
          style: {
            background: "linear-gradient(135deg, " + currentMember.color + "22, " + currentMember.color + "11)",
            border: "2px solid " + currentMember.color + "44",
            borderRadius: 20, padding: "16px 20px", marginBottom: 16,
          }
        },
          React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 14, marginBottom: 12 } },
            React.createElement("div", { style: { fontSize: 40 } }, currentMember.avatar),
            React.createElement("div", { style: { flex: 1 } },
              React.createElement("div", { style: { fontSize: 12, color: "#888" } }, currentMember.name + "の今週のポイント"),
              React.createElement("div", { style: { fontSize: 34, fontWeight: 900, color: currentMember.color, lineHeight: 1.1 } },
                myWeeklyPts, React.createElement("span", { style: { fontSize: 14, marginLeft: 4 } }, "pt")
              )
            ),
            React.createElement("div", { style: { textAlign: "center" } },
              React.createElement("div", { style: { fontSize: 34 } }, rank.emoji),
              React.createElement("div", { style: { fontSize: 10, color: "#888", fontWeight: 700 } }, rank.label)
            )
          ),
          React.createElement("div", null,
            React.createElement("div", { style: { display: "flex", justifyContent: "space-between", fontSize: 10, color: "#aaa", marginBottom: 4 } },
              React.createElement("span", null, rank.emoji + " " + rank.label),
              nextRank
                ? React.createElement("span", null, "次: " + nextRank.emoji + " " + nextRank.label + "（" + nextRank.min + "pt〜）")
                : React.createElement("span", null, "👑 最高ランク達成！")
            ),
            React.createElement("div", { style: { height: 7, background: "#e8e8e8", borderRadius: 4, overflow: "hidden" } },
              React.createElement("div", { style: { height: "100%", borderRadius: 4, background: currentMember.color, width: pctToNext + "%", transition: "width 0.6s ease" } })
            )
          )
        ),

        React.createElement("div", { style: { fontSize: 12, color: "#aaa", marginBottom: 8, fontWeight: 600 } }, "なにをした？タップ！"),
        React.createElement("div", { style: { display: "grid", gridTemplateColumns: "repeat(2, 1fr)", gap: 10 } },
          CHORES.map(chore =>
            React.createElement("button", {
              key: chore.id, onClick: () => addPoints(chore),
              style: {
                border: "none", borderRadius: 16, padding: "14px 12px",
                background: "#fff", boxShadow: "0 2px 10px rgba(0,0,0,0.06)",
                cursor: "pointer", textAlign: "left", transition: "all 0.15s",
                display: "flex", alignItems: "center", gap: 10,
              },
              onMouseEnter: e => e.currentTarget.style.transform = "scale(1.03)",
              onMouseLeave: e => e.currentTarget.style.transform = "scale(1)",
            },
              React.createElement("span", { style: { fontSize: 26 } }, chore.icon),
              React.createElement("div", null,
                React.createElement("div", { style: { fontSize: 13, fontWeight: 700, color: "#333" } }, chore.name),
                React.createElement("div", { style: { fontSize: 12, color: "#FF6B9D", fontWeight: 700 } }, "+" + chore.points + "pt")
              )
            )
          )
        )
      ),

      // RANKING TAB
      tab === "rank" && React.createElement("div", null,
        React.createElement("div", {
          style: { background: "linear-gradient(160deg, #1a1a2e 0%, #16213e 100%)", borderRadius: 20, padding: "18px 16px", marginBottom: 18 }
        },
          React.createElement("div", { style: { fontSize: 12, color: "#666", letterSpacing: 2, marginBottom: 2 } }, "LAST WEEK"),
          React.createElement("div", { style: { fontSize: 15, fontWeight: 900, color: "#fff", marginBottom: lastWeek ? 4 : 0 } }, "先週の TOP 3 🏆"),
          lastWeek && React.createElement("div", { style: { fontSize: 11, color: "#555", marginBottom: 12 } }, lastWeek.weekLabel),
          !lastWeek && React.createElement("div", { style: { fontSize: 12, color: "#444", marginTop: 8, textAlign: "center", padding: "10px 0" } }, "まだ記録がありません。今週がんばろう！"),
          lastWeek && lastWeek.top3.map((m, i) =>
            React.createElement("div", {
              key: i,
              style: {
                background: i === 0 ? "rgba(255,215,0,0.12)" : "rgba(255,255,255,0.05)",
                border: "1px solid " + (i === 0 ? "rgba(255,215,0,0.3)" : "rgba(255,255,255,0.07)"),
                borderRadius: 14, padding: "10px 14px", marginBottom: 8,
                display: "flex", alignItems: "center", gap: 10,
              }
            },
              React.createElement("div", { style: { fontSize: 22 } }, medalEmoji(i)),
              React.createElement("div", { style: { fontSize: 26 } }, m.avatar),
              React.createElement("div", { style: { flex: 1 } },
                React.createElement("div", { style: { fontWeight: 800, color: "#fff", fontSize: 14 } }, m.name),
                React.createElement("div", { style: { fontSize: 10, color: "#555", marginTop: 1 } }, getRank(m.points).emoji + " " + getRank(m.points).label)
              ),
              React.createElement("div", { style: { fontWeight: 900, color: m.color, fontSize: 18 } }, m.points + "pt")
            )
          )
        ),

        React.createElement("div", { style: { display: "flex", alignItems: "baseline", gap: 8, marginBottom: 12 } },
          React.createElement("div", { style: { fontSize: 13, fontWeight: 700, color: "#555" } }, "今週のランキング"),
          React.createElement("div", { style: { fontSize: 11, color: "#bbb" } }, formatWeekRange(currentWeekStart))
        ),
        sorted.map((m, i) => {
          const pt = wp[m.id] || 0;
          const r = getRank(pt);
          const max = wp[sorted[0].id] || 1;
          return React.createElement("div", {
            key: m.id,
            style: {
              background: "#fff", borderRadius: 18, padding: "14px 16px", marginBottom: 10,
              boxShadow: i === 0 && pt > 0 ? "0 4px 20px rgba(255,107,157,0.2)" : "0 2px 10px rgba(0,0,0,0.05)",
              border: i === 0 && pt > 0 ? "2px solid #FF6B9D44" : "2px solid transparent",
              display: "flex", alignItems: "center", gap: 12,
            }
          },
            React.createElement("div", { style: { fontSize: 22, width: 32, textAlign: "center" } }, medalEmoji(i)),
            React.createElement("div", { style: { fontSize: 30 } }, m.avatar),
            React.createElement("div", { style: { flex: 1 } },
              React.createElement("div", { style: { display: "flex", justifyContent: "space-between", marginBottom: 4 } },
                React.createElement("span", { style: { fontWeight: 700, color: "#333" } }, m.name),
                React.createElement("span", { style: { fontWeight: 900, color: m.color } }, pt + "pt")
              ),
              React.createElement("div", { style: { height: 6, background: "#f0f0f0", borderRadius: 3, overflow: "hidden" } },
                React.createElement("div", { style: { height: "100%", borderRadius: 3, background: m.color, width: (max > 0 ? (pt / max) * 100 : 0) + "%", transition: "width 0.5s ease" } })
              ),
              React.createElement("div", { style: { fontSize: 11, color: "#aaa", marginTop: 3 } }, r.emoji + " " + r.label)
            )
          );
        })
      ),

      // HISTORY TAB
      tab === "history" && React.createElement("div", null,
        React.createElement("div", { style: { fontSize: 12, color: "#aaa", marginBottom: 12, fontWeight: 600 } },
          "最近の記録　", React.createElement("span", { style: { color: "#ddd" } }, "（🗑️ で削除）")
        ),
        historyArr.length === 0
          ? React.createElement("div", { style: { textAlign: "center", padding: "40px 0", color: "#ccc", fontSize: 14 } },
              "まだ記録がありません", React.createElement("br"), "家事をやったら記録してみよう！"
            )
          : historyArr.map(h =>
              React.createElement("div", {
                key: h.id,
                style: { background: "#fff", borderRadius: 14, padding: "12px 14px", marginBottom: 8, boxShadow: "0 2px 8px rgba(0,0,0,0.05)", display: "flex", alignItems: "center", gap: 10 }
              },
                React.createElement("span", { style: { fontSize: 24 } }, h.icon),
                React.createElement("div", { style: { flex: 1 } },
                  React.createElement("div", { style: { fontSize: 14, fontWeight: 700, color: "#333" } }, h.avatar + " " + h.member + " — " + h.chore),
                  React.createElement("div", { style: { fontSize: 11, color: "#bbb", marginTop: 2 } }, formatDateTime(h.ts))
                ),
                React.createElement("div", { style: { fontWeight: 900, color: "#FF6B9D", fontSize: 14, marginRight: 6 } }, "+" + h.points + "pt"),
                React.createElement("button", {
                  onClick: () => setConfirmDelete(h),
                  style: { border: "none", background: "#FFF0F0", borderRadius: 10, width: 34, height: 34, fontSize: 15, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 },
                  onMouseEnter: e => e.currentTarget.style.background = "#FFCDD2",
                  onMouseLeave: e => e.currentTarget.style.background = "#FFF0F0",
                }, "🗑️")
              )
            )
      )
    )
  );
}

ReactDOM.createRoot(document.getElementById("app")).render(React.createElement(App));
</script>
</body>
</html>
