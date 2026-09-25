# CineFlash 🎬 — Notizie di cinema, minimal

App **iOS** (Expo SDK 57 · React Native 0.86 · React 19.2) che raccoglie tutte le notizie sul cinema dai principali siti italiani e mostra i film del momento con poster, trailer e uscite.

## Funzioni

- **Live**: polling automatico ogni 60s con pill "nuove notizie", badge NUOVO e notifiche locali (anche in background) per prevendite e novità
- **Tutto in-app**: gli articoli si leggono in una schermata integrata (WebView con azioni condividi/Safari) e i trailer si guardano con player nativo (expo-video per le anteprime Apple, embed YouTube per TMDB)
- **Notizie**: feed RSS aggregati (10 fonti italiane) con **hero in evidenza**, righe compatte con miniatura, **ricerca interna**, **salvataggio per dopo** (🔖) e condivisione; avvisi prevendite / film in arrivo in cima; pull-to-refresh
- **Salvati e watchlist**: le notizie salvate e i film con ⭐ restano sul dispositivo (AsyncStorage), filtro "⭐ Preferiti" nella tab Film
- **Design minimal + Liquid Glass**: superfici in vetro nativo (expo-glass-effect) su iOS 26, righe essenziali con hairline separator, tab bar nativa UITabBarController
- **Film**: funziona SUBITO con i cataloghi TMDB completi — la chiave API è **già inclusa** nell'app (nessuna configurazione):
  - **Ora al cinema / In uscita / Popolari** con voti, generi, durata e **trailer YouTube**
  - senza chiave (fallback automatico) → dati da **iTunes Search API di Apple**: nuovi arrivi e catalogo store italiano con **poster ufficiali e trailer**
  - puoi anche usare la tua chiave TMDB (v3 o token v4) dalle Impostazioni
  - dettaglio film con trama, trailer e link alle recensioni
- **AI locale ✨ (solo iPhone)**: un assistente che **spiega le notizie e i film in parole semplici**, con un modello LLM (classe 7B/8B) che gira **interamente sul telefono**:
  - **già installata all'apertura dell'app**: il modello si scarica e si carica in automatico al primo avvio, senza nessuna azione dell'utente
  - la pagina **AI" si presenta come "in manutenzione 🛠️"** (con barra di progresso) finché il modello non è pronto, poi **si sblocca da sola**
  - **mini banner di progresso** nella home ("Preparo l'AI… 47%") che sparisce quando il modello è pronto; un tocco apre la pagina AI
  - pulsante **"✨ Spiega con l'AI"** nell'articolo e nelle righe delle notizie
  - pulsante **"✨ Spiega con l'AI"** nel dettaglio film (spiega trama, genere, a chi consigliarlo)
  - chat in tempo reale (streaming) e suggerimenti rapidi
  - il modello GGUF (Llama 3.1 8B / Qwen 2.5 7B / Llama 3.2 3B) si scarica una sola volta da Hugging Face (~2-5 GB) e resta sul dispositivo
  - **download parallelo** con 6 connessioni simultanee al CDN (4-6x più veloce), resume per parte e assemblaggio via I/O nativo
  - accelerazione **Metal** su iPhone via llama.cpp (`llama.rn`) · **funziona anche offline** · nessun dato lascia il dispositivo
- **Impostazioni**: chiave API TMDB (opzionale), gestione **modelli AI locali** (download/eliminazione/Selezione), attiva/disattiva le fonti predefinite, aggiungi **qualsiasi feed RSS personalizzato**
- Cache offline (AsyncStorage): l'ultima notizie/film caricati restano visibili senza rete
- Dati salvati **solo sul dispositivo**, nessun account richiesto

## Avviare l'app su iPhone (da Windows)

### Opzione 1 — Expo Go (consigliata per provare subito)

1. Installa **Expo Go** dall'App Store sul tuo iPhone
2. Dal PC:

```bash
cd subzero
npx expo start
```

3. Collega PC e iPhone alla **stessa rete Wi-Fi** e scansiona il QR code con la **fotocamera** dell'iPhone (se non si connette: `npx expo start --tunnel`)

### Opzione 2 — App nativa con EAS Build

Serve un account Expo (gratuito) e, per TestFlight/dispositivi, un Apple Developer Account.

```bash
npm install -g eas-cli
eas login
eas build --platform ios --profile simulator   # simulatore
eas build --platform ios --profile production  # TestFlight
```

## AI locale (pagina ✨ AI)

L'AI gira **sul telefono** con [llama.rn](https://github.com/mybigday/llama.rn) (llama.cpp + Metal): nessuna API online, nessuna chiave, funziona offline.

### Come si attiva

Non serve fare nulla: all'**apertura dell'app** l'AI si prepara da sola. Al primo avvio scarica il modello consigliato (**Llama 3.1 8B**, 4.9 GB) mostrando la pagina AI "in manutenzione" con la percentuale; dalle volte successive è già pronto. Modelli alternativi (**Qwen 2.5 7B**, **Llama 3.2 3B** leggero) nella card **Impostazioni → AI locale ✨**.

Poi basta toccare **✨** su qualsiasi notizia, oppure **"✨ Spiega con l'AI"** nel dettaglio di un film.

> Il primo caricamento del modello richiede qualche secondo; le risposte arrivano in streaming token per token. Puoi disattivare i pulsanti ✨ dalle Impostazioni o eliminare il modello per liberare spazio.

> **Nota per lo sviluppo su Windows:** il postinstall di `llama.rn` estrae le librerie native con `tar`. Su Windows con Git Bash serve il tar nativo: `export PATH="/c/WINDOWS/system32:$PATH"` prima di `npm install`. Le build iOS vanno comunque fatte su macOS (o con EAS Build).

## Configurare TMDB (opzionale)

La tab Film funziona subito: la chiave TMDB è **già inclusa** nell'app. Se vuoi usare la tua:

1. Crea un account gratuito su [themoviedb.org](https://www.themoviedb.org/signup)
2. Impostazioni → API → richiedi una chiave (Developer, uso personale)
3. Apri CineFlash → **Impostazioni** → incolla la chiave v3 o il Read Access Token v4
4. Per tornare alla chiave inclusa: **↺ Ripristina la chiave inclusa**

## Struttura (expo-router)

```
subzero/
├── app/
│   ├── _layout.tsx            # Root stack
│   └── (tabs)/
│       ├── _layout.tsx        # Tab bar NATIVA (NativeTabs) + SF Symbols│   ├── index.tsx          # Notizie (feed RSS aggregato)
│       ├── movies.tsx         # Film (TMDB: poster, trailer, uscite)
│       └── settings.tsx       # Chiave TMDB + fonti RSS + modelli AI
├── ai.tsx                 # Pagina AI: chat che spiega notizie e film
└── src/
    ├── logic/news.ts          # Fetch/parsing RSS, dedup, "tempo fa", testo articoli per l'AI
    ├── logic/localAI.ts       # AI locale: modelli GGUF, download, chat llama.cpp
    ├── logic/itunes.ts        # Film senza chiave (iTunes Search API + nuovi arrivi)
    ├── logic/tmdb.ts          # Client TMDB opzionale (now playing, upcoming, trailer)
    ├── models/types.ts        # Tipi (NewsItem, Movie, Settings…)
    ├── storage/store.ts       # Impostazioni + cache AsyncStorage
    ├── storage/StoreContext.tsx
    ├── components/ui.tsx      # Componenti UI riutilizzabili
    ├── components/AIModelManager.tsx  # Gestione modelli AI (download, selezione)
    └── theme/index.ts         # Tema dark "sala cinema"
```

## Script

```bash
npm start        # dev server Expo
npx tsc --noEmit # typecheck
```
