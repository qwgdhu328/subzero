import React, { createContext, useContext } from "react";
import { useStore } from "./store";
import { useSavedNews, useWatchlist } from "./collections";
import { Settings } from "../models/types";

type Store = {
  settings: Settings;
  setSettings: (s: Settings) => void;
  update: (patch: Partial<Settings>) => void;
  loading: boolean;
  savedNews: ReturnType<typeof useSavedNews>;
  watchlist: ReturnType<typeof useWatchlist>;
};

const StoreContext = createContext<Store | null>(null);

export function StoreProvider({ children }: { children: React.ReactNode }) {
  const store = useStore();
  const savedNews = useSavedNews();
  const watchlist = useWatchlist();
  return (
    <StoreContext.Provider value={{ ...store, savedNews, watchlist }}>
      {children}
    </StoreContext.Provider>
  );
}

export function useStoreContext(): Store {
  const ctx = useContext(StoreContext);
  if (!ctx) throw new Error("useStoreContext fuori da StoreProvider");
  return ctx;
}
