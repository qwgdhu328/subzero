# App Review Notes — CineFlash

> Da incollare in **App Store Connect → App → versione → App Review Information → Notes**
> (e adattare per Play Console → Policy → App content, se pubblichi anche su Android).

---

## English (for the review team)

**CineFlash** is a movie-news reader. It aggregates public RSS feeds from Italian
film news sites, shows movie catalogs (now playing / upcoming) from TMDB and the
Apple iTunes Search API, and lets users open cinema websites to buy tickets
outside the app. There are **no accounts, no user-generated content, no ads, no
in-app purchases and no analytics**. All user data (saved articles, watchlist,
settings) is stored **locally on the device only**.

**Local AI feature (✨ "Explain with AI"):** the app bundles an on-device LLM
runtime (llama.cpp via the llama.rn library). On first use, the model weights
(GGUF file, 2–5 GB, e.g. Llama 3.1 8B) are downloaded **once** from Hugging Face
and stored in the app sandbox. **No user content is sent to any server**: all
inference runs on the phone and works offline. The download is optional — the
user can disable the AI feature entirely in Settings and the rest of the app
works normally. While the model downloads, the AI screen shows a progress page
("in manutenzione") and unlocks automatically when ready.

**Over-the-air updates:** the app uses **expo-updates** solely to deliver
JavaScript bug-fix bundles between app releases. It is never used to change the
app's purpose, UI, or features beyond what was reviewed, in line with
Guideline 3.3.2 / 2.5.2.

**TMDB API key:** the app ships with a free TMDB API key so catalogs work out of
the box; users may optionally replace it with their own key in Settings
(themoviedb.org, free tier). Movie data and posters are provided by TMDB but this
product uses the TMDB API but is not endorsed or certified by TMDB.

**Location permission:** requested only when the user taps "Sort cinemas by
distance" during ticket booking (booking happens on the cinema's own website).
Used in memory only, never stored or transmitted.

**Testing tips:** any RSS feed can be toggled in Settings → "Fonti notizie".
To see the AI download flow, open the AI tab after a fresh install; on devices
where the model is already cached, the ✨ button on any article demonstrates the
feature immediately. If a live feed is unreachable during review, the app still
shows cached content — please relaunch it once.

**Contact:** [nome + email + telefono in formato internazionale, es. +39 …]

---

## Italiano (per tua referencia / eventuali appellos)

CineFlash aggrega notizie di cinema da feed RSS pubblici e mostra cataloghi film
(TMDB / iTunes Search API). Nessun account, nessun UGC, nessuna pubblicità,
nessun IAP, nessun analytics: i dati utente restano solo sul dispositivo.

L'AI (✨) gira **interamente sul telefono** (llama.cpp): il modello GGUF si
scarica una volta sola da Hugging Face nella sandbox dell'app; nessun contenuto
utente viene inviato online. Disattivabile dalle Impostazioni.

**expo-updates** è usato solo per fix JS tra le release (Guideline 3.3.2 / 2.5.2),
mai per cambiare funzionalità rispetto a quanto revisionato.

La chiave TMDB inclusa è quella gratuita per sviluppatori; l'utente può
sostituirla con la sua. Il permesso posizione serve solo per ordinare i cinema
per distanza in fase di prenotazione (la prenotazione avviene sul sito del
cinema), non viene mai salvato o trasmesso.

---

## Checklist finale prima del submit (fuori dal codice)

- [ ] Allegato **ADPLA 14 (EU)** accettato in ASC (entro 1 ott 2026)
- [ ] Questionario **age rating** compilato (con AI generativa: valuta 16+, verifica "Unrestricted AI" nel questionario)
- [ ] **Privacy nutrition labels**: "Data Not Collected" (coerente con `ios.privacyManifests` in app.json)
- [ ] **Social media capability question** risposta in ASC
- [ ] Screenshot set **6.9"** caricato; nessun riferimento ad Android nelle creatività
- [ ] Se pubblichi su Play: **package name `com.cineflash.app` registrato** entro il 30 set 2026 + questionario content rating completo
