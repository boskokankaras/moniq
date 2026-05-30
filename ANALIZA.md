# Moniq — Detaljna analiza aplikacije

**Datum:** 2026-05-30 · **Fajl:** `index.html` (2655 linija, vanilla JS + Supabase, GitHub Pages)
**Metod:** 3 paralelna pregleda (security/sync · performanse/mobile · korektnost/a11y/kvalitet), pročitan cijeli fajl.

> Napomena: app NE koristi Claude/AI API — ovo je čist code-review, ne `/claude-api` zadatak.

**Ukupno: ~50 jedinstvenih problema** — 3 KRITIČNA · 13 VISOKIH · 20 SREDNJIH · 14 NISKIH.

> **✅ 30.05.2026 — sva 3 KRITIČNA riješena** (P1 RLS, P2 XSS, P3 initFP). Detalji ispod.

---

## 🔴 A. KRITIČNO (bezbjednost / app puca)

**P1 — [KRITIČNO] ✅ RIJEŠENO** — Supabase RLS · L516, 721, 841, 1898–1922, 2529–2550, 828
> Potvrđeno: `expenses` je imao `Public access` politiku (`USING/WITH CHECK true`) koja je poništavala per-user politike. **Obrisana migracijom** `drop_public_access_policy_on_expenses`. Sad važe `select_own/insert_own/update_own/delete_own`. `income_entries` i `user_settings` su već bili ispravni. Svih 359 redova ima `user_id` (1 korisnik) → ništa se ne lomi. Advisor čist.
Svi upiti (`select('*')`, `update().eq('id')`, `delete().eq('id')`) idu **bez `user_id` filtera** — oslanjaju se isključivo na Row-Level Security. Ako RLS nije uključen i ispravno podešen na Supabase projektu, **svaki ulogovan korisnik može da čita/mijenja/briše tuđe troškove, primanja i postavke**. `seedIfEmpty` broji *globalne* redove. → **Hitno provjeriti RLS na `expenses`, `income_entries`, `user_settings`.**

**P2 — [KRITIČNO] ✅ RIJEŠENO** — Stored XSS · L1037, 1242, 1430, 1870, 2598
~~`e.method` se ubacuje neescapovano...~~ **Escapovano preko `esc()`:** `e.method` (4 mjesta), `m.name` (postavke ×2), te profil polja `first_name/last_name/username/email/initial/birth_date`. Vrijednosti se i dalje čuvaju sirove, ali se renderuju escapovano → XSS zatvoren.

**P3 — [KRITIČNO] ✅ RIJEŠENO** — Dodavanje primanja pucalo · L2512
`openAddIncomeSheet()` zvao `initFP()` (nedefinisano) → `ReferenceError`. **Poziv uklonjen** (sheet koristi native `<input type=date>`, flatpickr ne treba). Napomena: `addIncome`/`removeIncome` (sa `saveIncomeEntries`) su **mrtav kod, niko ih ne zove** — ostavljeni za cleanup (Talas 5), ne izvršavaju se.

---

## 🟠 B. STABILNOST (VISOKO)

**P4 — Duplikat `onAuthStateChange`** · L774 + L2200
Listener se registruje u `init()` i ponovo u `authSubmit()`. Posle jednog login-a u istom učitavanju, svaki auth event okida 2× (dupli `showLoginScreen`, dupli reset state-a).

**P5 — Realtime kanali se nikad ne odjavljuju** · L702–718
`connectSupabase()` pravi nove kanale (`exp-rt`, `inc-rt`, `settings-rt`) svaki put (i na re-login preko `authSubmit` L2206) bez `removeChannel`. Posle N login ciklusa svaka DB izmjena okida render N puta.

**P6 — `handleRT` rendera CIJELI view na svaki realtime event** · L916–923, 730
Mutira jedan element pa zove `renderView(APP.view)` (pun `innerHTML` rebuild). Tvoj vlastiti unos se vraća kroz subscription → svaki add = lokalni render + drugi pun realtime render. Burst = freeze.

**P7 — Pretraga bez debounce-a → pun rebuild na svaki karakter** · L1258 (troškovi), L1202 (primanja)
`oninput=...renderExpenses()` re-filtrira, radi `[...new Set()].sort()` ×2, group-by, rebuilduje cijeli `innerHTML`, re-attachuje swipe listenere, pa ručno vraća kursor (L1270). 6 slova = 6 punih re-rendera. Na 1000+ unosa — vidljiv lag.

**P8 — `renderDashboard` radi ~14 punih prolaza kroz `APP.expenses` po renderu** · L943–1162
9× `.filter`, `.reduce`, `[...sort]` (L960), `Math.max(...)` (L963), `[...new Set()]` (L1062) — sve iz početka na svaki render, čak i kad samo proširiš "Posljednje" (`loadMoreRecent` L1728 re-pokreće cijeli pipeline). ~30×N operacija po paintu.

**P9 — 405KB vendor JS inline + `no-store` keš** · L5–7, 2631 (Supabase ~197KB), 2639 (Chart.js ~208KB)
Biblioteke su zalijepljene **inline** u HTML, a `<meta Cache-Control: no-store>` zabranjuje keširanje. Svaki `location.reload()` (pull-to-refresh, update pill) ponovo skida **684KB** i parsira 405KB JS-a. Bolno na mobilnom internetu.

**P10 — Rate brojač "klizi" + nema rollback** · L1893, 1675, 765
`incRatePaid` poveća `placene_rate` lokalno pa ubaci trošak; ako insert padne — **nema povratka** (samo log). `rate_entries` živi samo u localStorage i sinhronizuje se kao blob → na dva uređaja last-write-wins gubi increment / dvostruko broji.

**P11 — Djelimičan seed ostavlja pola-popunjenu bazu** · L835–837
`seedIfEmpty` ubacuje 7 chunkova preko `Promise.all`; ako chunk padne, prethodni su već upisani pa `throw`. Sljedeći put `count>0` → nikad ne re-seeduje. Korisnik trajno ostaje sa djelimičnim podacima.

**P12 — Unos primanja bez try/catch, `closeAllSheets()` prije await-a** · L2529, 2541, 2550, 2072
Na grešku mreže sheet je već zatvoren, korisnik vidi `alert('Greška: ...')` sa tehničkom porukom, a **uneseni podaci su izgubljeni**. Isti obrazac u edit/remove/dup primanja.

**P13 — Optimistički keš se bezuslovno pregazi sa `loadAll`** · L780–792, 843
Keš se odmah renderuje, pa pozadinski `loadAll` zamijeni `APP.expenses` serverskim podacima. Lokalna izmjena napravljena tokom sync prozora (prije round-tripa) se tiho gubi. Nema merge/verzionisanja.

**P14 — A11y: sve interaktivno je `<div onclick>` bez tastature** · svuda
Nav, hero tačke, filter čipovi, redovi, mjesec headeri — sve `<div>`/`<span>` sa `onclick`. **Nula** `tabindex`/`role`/`onkeydown` u fajlu. Neupotrebljivo bez miša, neprijateljski za screen-reader. (Detaljnije u sekciji D.)

**P15 — `checkForUpdate` se nikad ne zove na učitavanju** · L847–860
Pozvan je samo unutar `syncAndRefresh` (ručni sync). Pill "Nova verzija" se **nikad ne pojavi** pri normalnom otvaranju → auto-update praktično mrtav.

---

## 🟡 C. PERFORMANSE (SREDNJE)

**P16 — `backdrop-filter: blur()` na svakom redu iznad animirane pozadine** · CSS, ~21 selektora
`.card`, `.expense-item`, `.method-card`, `.amount-pill`... svaki nosi `blur(20px)`. `body::before` je fiksni sloj sa `animation:bgShift 15s` iza svih blur-ova → iOS Safari re-sample-uje blur 60fps cijelo vrijeme. **Glavni uzrok scroll-janka i trošenja baterije** na starijim iPhone-ima.

**P17 — Favicon zahtjev po redu, ponovo na svaki render** · L1359, 1407–1416
`getExpLogo`/`getSubLogo` emituju `<img src="google.com/s2/favicons...">` po redu. Velika lista = stotine zahtjeva ka Google servisu na svaki `innerHTML` rebuild; `onerror` prepisuje `outerHTML` (reflow).

**P18 — Sinhroni `localStorage.setItem(JSON.stringify())` na svaki render** · L2466, 1172, 929
`saveUiState()` na vrhu `renderExpenses`/`renderView` → blokira main thread na svaki karakter pretrage.

**P19 — `fmt()` nije memoizovan** · L668
`CURRENCIES.find()` + `toLocaleString('de-DE', {...})` za **svaki** iznos, stotine puta po renderu. Nema keširane `Intl.NumberFormat` instance.

**P20 — `initIncLongPress` attachuje 4 listenera po redu primanja na svaki render** · L1209, 1980
Troškovi koriste jedan delegirani listener (`_lpBound` L2003) — primanja bi trebalo isto.

**P21 — Settings sync gazi cijeli blob (last-write-wins)** · L531, 705
`pushUserSettings` upsertuje cijeli `SYNCED_KEYS` blob bez verzije. Dva uređaja mijenjaju različite ključeve u 600ms → jedan se gubi (npr. A toggluje `dark`, B reordera widgete → jedno propadne).

**P22 — Dva loading-timeout overlay-a (12s + 15s) mogu da bljesnu preko app-a koja radi** · L2079, 352
Spor-ali-uspješan load koji završi ~13s ipak prikaže "Sporo učitavanje" panel na 12s.

**P23 — `Promise.all([loadAll, loadIncome])` — pad primanja truje status troškova** · L700
Ako `loadIncome` padne, cijeli connect odbacuje iako su troškovi učitani → "offline" status iako su podaci tu.

**P24 — `fetchRates` na grešku ostavlja stari kurs tiho** · L630–637
Na ne-JSON odgovor `r.json()` baci, `curRate` ostaje star, "⏳ Učitavam kurs..." može da ostane. Iznosi tiho ostanu u EUR.

**P25 — Kurs iz keša može dati `NaN`** · L618, 625
Ručno iskvaren `{"rate":"abc"}` prolazi truthy provjeru i postavi `curRate="abc"` → svi iznosi `NaN €`. Nema numeričke validacije.

**P26 — `withTimeout` ne otkazuje zahtjev; kanali bez timeout-a** · L691, 700
Timeout odbaci ali Supabase zahtjev i dalje radi pa može da resolve-uje kasnije sa starim podacima. Websocket koji visi ostavlja indikator zaglavljen na "Sinkronizovano".

**P27 — Više `localStorage.setItem` bez quota/try-catch** · L1552, 822, 1546, 1718, 1356, 559
Na `QuotaExceededError` bacaju i prekidaju funkciju (npr. dodavanje rate tiho padne nakon što je unos već u memoriji).

---

## 🔵 D. PRISTUPAČNOST (a11y)

**P28 — Nema `<label for>` veza** · L273, login L2163
Inputi imaju `id` ali labele nisu povezane; login ima samo `placeholder`. Screen-reader čita "edit text" bez imena.

**P29 — Kontrast pada WCAG AA** · L15–16
`--sub:#6b7280` na svijetloj pozadini ≈ 3.9:1 (treba 4.5:1) na 10–14px tekstu (meta, chip labele, budžet labele).

**P30 — "Sakrij iznose" ostavlja vrijednosti u DOM-u** · L677, 1117
`fmtP` renderuje `data-v="${fmt(v)}"`; `.hidden` samo vizuelno maskira. Stvarni iznos je u atributu — trivijalno otkriti, screen-reader može pročitati.

**P31 — Nema `prefers-reduced-motion`** · konfeti L2417, spinneri, sheet slide, PTR
Nijedna animacija nije gejtovana → problem za vestibularno osjetljive korisnike.

**P32 — Touch mete ispod 44px** · L1204 (×), L187 (dup-btn 2px), L270 (sheet-close 28px), hero dugmad 30×26px

**P33 — Fokus se ne hvata ni vraća u sheet-ovima/meniju** · L1940, 2034
`openSheet` ne fokusira sheet, `closeAllSheets` ne vraća fokus na trigger; `Escape` ne zatvara.

**P34 — Logo `<img>` bez `alt`** · L1410–1415

---

## ⚪ E. KVALITET KODA / MRTAV KOD

**P35 — `renderCharts()` je mrtav no-op** ali se zove na svaki dashboard render (L1160); `barChart`, `chartColor`, `gridColor` neiskorišćeni (L598, 1164).

**P36 — `buildSliderWidget` ignoriše 3 od 5 parametara** · L1352
Cijela donut/slide infrastruktura (`switchWSlide`, `renderWDonut`, `_wDonutData`) je ožičena ali donut se nikad ne renderuje.

**P37 — Nekonzistentni nazivi mjeseci** · L586 `MN` vs L1687/1704 `MN2`
"Jun" vs "Juni", "Avgust" vs "August" — različit ispis zavisno od koda.

**P38 — `parseFloat` umjesto `parseAmt` za rate "ukupno"** · L1886
Zarez-decimala "898,08" → `parseFloat` vrati `898`. `submitAddRate` (L1638) ispravno koristi `parseAmt` — nekonzistentno.

**P39 — `saveInitialBalance` može upisati `NaN`** · L1527
`parseAmt(amt)` bez provjere → hero kartica prikaže `NaN`.

**P40 — Kategorijski regex over-match** · L571
`bov`, `carina`, `mol`, `idea` bez granica riječi → hvataju podstringove u nevezanim opisima.

**P41 — `pct` može preći 100%** · L1559
`buildRateWidget` ne štiti `Math.round(paid/total*100)` ako iskvaren `rate_entries` ima `placene_rate>broj_rata`.

**P42 — `localStorage.setItem` globalno monkey-patchovan** · L765
Svaki upis u localStorage (i iz biblioteka) okida `_schedPush`. Fragilno, "action-at-a-distance".

**P43 — Mrtve reference / fantomi:** `user-bn-avatar` (L2228, nema u DOM-u), `--sat` (L2048, nikad definisan → safe-area clamp inertan), `_wallet` (L1099, obje grane iste), "Platne kartice" FAB stub `alert('Uskoro')` (L428).

**P44 — Duplikacija:** `getExpLogo`/`getSubLogo` ~20 istih regex→domen parova; `setSavingsMode`/`setKesSavingsMode` skoro identične; eye-toggle SVG dupliran 4×.

**P45 — Magični brojevi / globali:** kartica balans `77268.93` hardkodiran na 4 mjesta (L997, 1008, 1479, 1686); `window._authMode` (L2164); inline timeouti.

---

## ⚪ F. SITNIJE (NISKO)

**P46 — CSV injection u eksportu** · L1719 — `desc` koji počinje sa `=`/`+`/`-`/`@` može izvršiti formulu u Excel/Sheets.
**P47 — Nestabilan sort primanja** · L727 — bez id tiebreak-a (troškovi imaju, L918) → red istog dana varira.
**P48 — `migrateUserExpenses` bezuslovni UPDATE na svako učitavanje** · L2618 — pad ovdje ruši cijeli connect (prvi await L697).
**P49 — `parseAmt` edge case-ovi** · L601 — "1.234.56"→1.234, "1-2"→1.
**P50 — Nemapirani SVG / 314 inline `style=`** — naduvava nekeširani, neminifikovani fajl; nema `<symbol>`/`<use>`.

---

## 🎯 Preporučeni redoslijed sređivanja

**Talas 1 — Bezbjednost (hitno, nevidljivo korisniku)**
P1 (potvrdi RLS) · P2 (escape method/profil) · P46 (CSV)

**Talas 2 — Polomljeno + crash-prone**
P3 (initFP) · P4 (dupli auth) · P5 (unsubscribe kanali) · P12 (try/catch primanja) · P11 (seed)

**Talas 3 — Performanse (lag koji se osjeti)**
P7 (debounce search) · P6 (debounce realtime render) · P8 (memoize dashboard prolazi) · P19 (Intl.NumberFormat) · P16 (smanji blur/animaciju) · P9 (izdvoji JS + keširaj)

**Talas 4 — Robusnost podataka**
P10 (rate rollback) · P13 (merge umjesto pregazi) · P21 (settings konflikt) · P25/P39 (NaN guard) · P27 (quota)

**Talas 5 — Pristupačnost + čišćenje**
P14/P28–P34 (a11y) · P35–P45 (mrtav kod, duplikati, magični brojevi)
