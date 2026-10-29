#!/bin/sh
# For /outil vitesse: where the time of the last runs of the pack went, and what slowed or blocked them, read from the
# lines the pack plugin writes at the end of each run of a command (point 29 of the plugin): the model of the pilot,
# its subagents, its tools and the questions on the path of the run; for the model, every session included: its wait
# before the first token (the first request of a session, then the next ones), its thinking, its writing, its speed;
# the retries, the answers a gateway held back, the silences of the stream, the summaries of the context. Then the
# points to look at, each with where to act. Read-only. The output is shown as it is to the developer, so it is in
# French.
# Usage: vitesse.sh [<number of runs, 10 by default>] [<command: go, fix, fortify, tests…>]
# The file: openrd-pack-runs.tsv (and .1) in the folder of the log of the plugin ($OPENRD_PACK_LOG_DIR, set by the
# plugin for its scripts; otherwise ~/oc2/data/opencode/log for an OpenCode v2 next to 1.19, then
# $XDG_DATA_HOME/opencode/log, ~/.local/share/opencode/log).

LC_ALL=C
export LC_ALL

count=10
only=""
for arg in "$@"; do
  case "$arg" in
    ''|*[!0-9]*) only=${arg#/} ;;
    *) count=$arg ;;
  esac
done
[ "$count" -ge 1 ] 2>/dev/null || count=10
[ "$count" -le 200 ] || count=200

file=""
for dir in "${OPENRD_PACK_LOG_DIR:-}" "$HOME/oc2/data/opencode/log" "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/log" "$HOME/.local/share/opencode/log"; do
  [ -n "$dir" ] || continue
  if [ -f "$dir/openrd-pack-runs.tsv" ] || [ -f "$dir/openrd-pack-runs.tsv.1" ]; then
    file="$dir/openrd-pack-runs.tsv"
    break
  fi
done
if [ -z "$file" ]; then
  echo "Vitesse des runs : aucune mesure pour l'instant. Le plugin du pack écrit une ligne à la fin de chaque run d'une commande (/go, /fix, /fortify, /tests, /push…) ; lance-en un, puis /outil vitesse."
  exit 0
fi

{
  [ -f "$file.1" ] && cat "$file.1"
  [ -f "$file" ] && cat "$file"
} | awk -F '\t' -v count="$count" -v only="$only" '
  # seconds as « 12 s », « 2 min 05 s », « 1 h 04 min »
  function duration(s,   h, m) {
    s = int(s + 0.5)
    if (s < 60) return s " s"
    if (s < 3600) return int(s / 60) " min " sprintf("%02d", s % 60) " s"
    h = int(s / 3600); m = int((s % 3600) / 60)
    return h " h " sprintf("%02d", m) " min"
  }
  function decimal(x,   t) { t = sprintf("%.1f", x); sub(/\.0$/, "", t); sub(/\./, ",", t); return t }
  function pct(part, whole) { return whole > 0 ? int(100 * part / whole + 0.5) : 0 }
  # the local time of the run ("2026-10-26 11:12", field at) as "26/10 11:12"; an older line: its UTC date
  function when(r,   t) { t = v[r, "at"]; if (t == "") t = stamp[r]; return substr(t, 9, 2) "/" substr(t, 6, 2) " " substr(t, 12, 5) }
  # "label:n:seconds,label:n:seconds" added to the totals of the runs shown
  function addList(text, names, ns, ss, total,   items, n, i, part, k) {
    n = split(text, items, ",")
    for (i = 1; i <= n; i++) {
      if (split(items[i], part, ":") != 3) continue
      k = part[1]
      if (!(k in ns)) { total[0]++; names[total[0]] = k }
      ns[k] += part[2]; ss[k] += part[3]
    }
  }
  # the k entries of a list with the most seconds: « coder 5 (12 min 03 s), … »
  function top(names, ns, ss, size, k,   used, out, j, i, best, bestS) {
    out = ""
    for (j = 1; j <= k; j++) {
      best = ""; bestS = -1
      for (i = 1; i <= size; i++) if (!(names[i] in used) && ss[names[i]] > bestS) { best = names[i]; bestS = ss[names[i]] }
      if (best == "") break
      used[best] = 1
      out = out (out == "" ? "" : ", ") best " " ns[best] " (" duration(ss[best]) ")"
    }
    return out
  }
  BEGIN { asize[0] = 0; tsize[0] = 0; an[0] = ""; tn[0] = ""; ann["-"] = 0; ans["-"] = 0; tnn["-"] = 0; tns["-"] = 0 }
  $2 == "run" {
    delete f
    for (i = 3; i <= NF; i++) {
      eq = index($i, "=")
      if (eq > 1) f[substr($i, 1, eq - 1)] = substr($i, eq + 1)
    }
    if (only != "" && f["command"] != only) next
    n++
    line[n] = $0; stamp[n] = $1
    for (k in f) v[n, k] = f[k]
  }
  END {
    if (n == 0) {
      print "Vitesse des runs : aucune mesure" (only != "" ? " pour /" only : "") " pour l'"'"'instant."
      exit 0
    }
    first = n - count + 1; if (first < 1) first = 1
    shown = n - first + 1
    print "⏱ Vitesse " (shown == 1 ? "du dernier run" : "des " shown " derniers runs") (only != "" ? " de /" only : "") " (sur " n " mesuré" (n > 1 ? "s" : "") ", depuis le " when(1) ") :"
    print ""
    print "| Quand | Commande | Durée | Modèle du pilote | Sous-agents | Outils | Questions | 1er token (moy. / max) | Nouveaux essais | Issue |"
    print "|---|---|---|---|---|---|---|---|---|---|"
    for (r = first; r <= n; r++) {
      cmd = "/" v[r, "command"] (v[r, "key"] != "" ? " " v[r, "key"] : "")
      essais = v[r, "retries"] + 0 > 0 ? v[r, "retries"] " (" duration(v[r, "retry_wait"]) ")" : "—"
      quest = v[r, "questions"] + 0 > 0 ? duration(v[r, "questions"]) : "—"
      print "| " when(r) " | " cmd " | " duration(v[r, "total"]) " | " duration(v[r, "top_model"]) " | " duration(v[r, "top_subagents"]) " | " duration(v[r, "top_tools"] + v[r, "prep"]) " | " quest " | " decimal(v[r, "ttft_avg"]) " s / " duration(v[r, "ttft_max"]) " | " essais " | " (v[r, "outcome"] == "-" ? "—" : v[r, "outcome"]) " |"
      T += v[r, "total"]; PM += v[r, "top_model"]; SA += v[r, "top_subagents"]; TO += v[r, "top_tools"]; PR += v[r, "prep"]; Q += v[r, "questions"]
      ST += v[r, "steps"]; W += v[r, "wait"]; TH += v[r, "think"]; WR += v[r, "write"]
      CN += v[r, "cold_n"]; CS += v[r, "ttft_cold"] * v[r, "cold_n"]; WN += v[r, "warm_n"]; WS += v[r, "ttft_warm"] * v[r, "warm_n"]
      if (v[r, "ttft_max"] + 0 > TMAX) TMAX = v[r, "ttft_max"] + 0
      if (v[r, "stall_max"] + 0 > SMAX) SMAX = v[r, "stall_max"] + 0
      STALLS += v[r, "stalls"]; B += v[r, "buffered"]; R += v[r, "retries"]; RW += v[r, "retry_wait"]
      CP += v[r, "compactions"]; CT += v[r, "compaction"]; L += v[r, "loops"]
      # the tokens of the generation, as the server counted them, or estimated from the characters streamed
      tok = v[r, "tokens_out"] + v[r, "tokens_reasoning"]
      if (tok == 0 && v[r, "chars"] + 0 > 0) { tok = v[r, "chars"] / 3.5; EST = 1 }
      TOK += tok
      addList(v[r, "agents"], an, ann, ans, asize)
      # the requests of each agent, those that called tools, and their tool calls (agent:requests:with tools:calls)
      nb = split(v[r, "batch"], bl, ",")
      for (i = 1; i <= nb; i++) {
        if (split(bl[i], bp, ":") != 4) continue
        if (!(bp[1] in BS)) { BN++; BA[BN] = bp[1] }
        BS[bp[1]] += bp[2]; BT[bp[1]] += bp[3]; BC[bp[1]] += bp[4]
      }
      addList(v[r, "tools"], tn, tnn, tns, tsize)
      if (split(v[r, "tool_max"], tm, ":") == 2 && tm[2] + 0 > XMAX) { XMAX = tm[2] + 0; XNAME = tm[1] }
    }
    print ""
    print "Où passe le temps (" (shown == 1 ? "ce run" : "ces " shown " runs") ", " duration(T) ") : sous-agents " pct(SA, T) " %, modèle du pilote " pct(PM, T) " %, outils du pilote " pct(TO, T) " %, préparation " pct(PR, T) " %, questions " pct(Q, T) " %."
    gen = TH + WR
    speed = gen > 0 ? TOK / gen : 0
    cold = CN > 0 ? CS / CN : 0
    warm = WN > 0 ? WS / WN : 0
    model = "Le modèle, toutes sessions : " ST " requêtes ; 1er token après " decimal(ST > 0 ? W / ST : 0) " s en moyenne"
    if (CN > 0 && WN > 0) model = model " (" decimal(cold) " s pour la première requête d'"'"'une session, " decimal(warm) " s pour les suivantes)"
    if (gen > 0) model = model " ; réflexion " pct(TH, gen) " %, rédaction " pct(WR, gen) " % ; ≈ " int(speed + 0.5) " tokens/s" (EST ? " (estimé en partie sur les caractères)" : "")
    print model "."
    if (asize[0] > 0) print "Sous-agents : " top(an, ann, ans, asize[0], 6) "."
    if (tsize[0] > 0) print "Outils les plus longs : " top(tn, tnn, tns, tsize[0], 5) "."
    # the tool calls each request carries, by agent: the agents with the most requests first
    if (BN > 0) {
      out = ""
      for (j = 1; j <= BN && j <= 6; j++) {
        best = ""; bestS = -1
        for (i = 1; i <= BN; i++) if (!(BA[i] in usedB) && BS[BA[i]] > bestS) { best = BA[i]; bestS = BS[BA[i]] }
        if (best == "") break
        usedB[best] = 1
        out = out (out == "" ? "" : ", ") best " " BS[best] " requêtes" (BT[best] > 0 ? " (" decimal(BC[best] / BT[best]) " appel" (BC[best] / BT[best] >= 2 ? "s" : "") " d'"'"'outil par requête)" : "")
      }
      print "Requêtes au modèle, par agent : " out "."
    }
    print ""
    print "Points à regarder :"
    points = 0
    if (R > 0) { points++; print "- Le serveur du modèle a échoué " R " fois (une passerelle en 504 ou 503, le plus souvent) : " duration(RW) " d'"'"'attente avant les nouveaux essais, et chaque essai repart de zéro. Côté plateforme : le délai de la passerelle pour les réponses en streaming (COMMANDES.md, « Qwen 3.8 »)." }
    if (B > 0) { points++; print "- " B " réponse" (B > 1 ? "s" : "") " arrivée" (B > 1 ? "s" : "") " d'"'"'un seul bloc après une longue attente : la passerelle garde le streaming en tampon. L'"'"'interface reste muette pendant la réponse, et une réponse longue finit en 504. Côté plateforme : streaming sans tampon (nginx : proxy_buffering off ; COMMANDES.md, « Qwen 3.8 »)." }
    if (SMAX >= 60) { points++; print "- Le flux du modèle s'"'"'est arrêté jusqu'"'"'à " duration(SMAX) " au milieu d'"'"'une réponse (" STALLS " fois plus d'"'"'une minute) : serveur saturé ou passerelle. OpenCode attend 15 min sans rien recevoir avant de réessayer : chunkTimeout du provider (COMMANDES.md, « Qwen 3.8 »)." }
    if (WN > 0 && CN > 0 && warm >= 10 && warm >= 0.7 * cold) { points++; print "- Les requêtes suivantes d'"'"'une session attendent " decimal(warm) " s avant leur 1er token, la première " decimal(cold) " s : quand le serveur garde le début de la conversation (prefix caching), une suivante ne relit que ce qui s'"'"'ajoute et part bien plus vite. Côté plateforme : le prefix caching de vLLM, et l'"'"'affinité de session (en-tête x-session-affinity) s'"'"'il y a plusieurs répliques." }
    else if (ST > 0 && W / ST >= 15) { points++; print "- " decimal(W / ST) " s en moyenne avant le 1er token : le serveur fait attendre les requêtes (trop de requêtes en même temps, ou des contextes très longs). Moins de runs en parallèle, ou plus de capacité côté plateforme." }
    if (speed > 0 && speed < 20) { points++; print "- Génération lente : ≈ " int(speed + 0.5) " tokens/s. Côté plateforme : la charge du serveur, et la génération de plusieurs tokens à la fois de Qwen (MTP ; COMMANDES.md, « Qwen 3.8 »)." }
    if (gen > 0 && TH >= 0.6 * gen && TH >= 60) { points++; print "- La réflexion fait " pct(TH, gen) " % de la génération du modèle (" duration(TH) "). Le levier sans toucher au code : l'"'"'effort de réflexion par agent (reasoning_effort, le pilote d'"'"'abord), que le plugin envoie maintenant ; à mesurer ici avant et après (COMMANDES.md, « Qwen 3.8 »)." }
    if (CP > 0) { points++; print "- " CP " résumé" (CP > 1 ? "s" : "") " du contexte (" duration(CT) ") : le contexte s'"'"'est rempli. limit.context au vrai maximum du serveur ; OpenCode v2.1.4 peut préparer le résumé en arrière-plan (experimental.background_compaction ; COMMANDES.md, « Qwen 3.8 »)." }
    if (T > 0 && PR >= 0.1 * T && PR >= 60) { points++; print "- Préparation (les scripts avant le modèle, dont git fetch) : " pct(PR, T) " % (" duration(PR) ") : le réseau vers GitLab." }
    if (XMAX >= 120 && XNAME !~ /\.sh/) { points++; print "- L'"'"'appel le plus long : " XNAME " (" duration(XMAX) ") : un serveur MCP ou un outil lent (le plugin coupe un appel MCP après 5 min)." }
    if (L > 0) { points++; print "- " L " réponse" (L > 1 ? "s" : "") " coupée" (L > 1 ? "s" : "") " en boucle : le plugin les relance avec une pénalité de répétition." }
    if (Q > 0) { points++; print "- Tes réponses aux questions : " duration(Q) " d'"'"'attente (le run attendait, pas le modèle). Pour un run sans toi : « sans question » après /go, /fix ou /fortify (les réponses recommandées, notées pour la review)." }
    # the agents that send one tool call per request where several independent ones could go together
    single = ""; ALLN = 0; ALLLOW = 0
    for (i = 1; i <= BN; i++) {
      a = BA[i]
      if (BT[a] < 20) continue
      ALLN++
      if (BC[a] / BT[a] < 1.3) { ALLLOW++; single = single (single == "" ? "" : ", ") a " " decimal(BC[a] / BT[a]) }
    }
    if (single != "") { points++; print "- Un seul appel d'"'"'outil par requête, ou presque (" single ") : des lectures ou des modifications indépendantes qui pourraient partir ensemble. Chaque requête renvoie tout le contexte au serveur et compte dans sa limite de débit." (ALLN >= 2 && ALLLOW == ALLN ? " Tous les agents sont dans ce cas : le serveur ne renvoie peut-être qu'"'"'un appel par réponse (le parser des appels d'"'"'outils du modèle dans vLLM, ou la passerelle) : à vérifier avec l'"'"'équipe qui l'"'"'héberge." : "") }
    if (points == 0) print "- Rien d'"'"'anormal dans ces runs : le temps est celui du modèle et de la machine."
  }
'
