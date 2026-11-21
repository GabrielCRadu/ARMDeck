// Tiles in the Steam library through Steam's live API, the way Steam's own "Add a Non-Steam Game"
// does it: Steam writes shortcuts.vdf itself, so no restart is needed and nothing edits the file
// behind its back (the model of Armada's armada-store and Nova-Deck's novadeck-stores).

declare const SteamClient: any;
declare const appStore: any;

export type TileSpec = {
  key: string;
  name: string;
  exe: string;
  start_dir: string;
  options: string;
  compat_tool?: string;
  kind?: string; // a game tile: its system, "windows" or "native"
};

export async function addTile(spec: TileSpec): Promise<number> {
  const apps = SteamClient?.Apps;
  if (!apps?.AddShortcut) throw new Error("Steam's shortcut API is not available");
  const appid = Number(await apps.AddShortcut(spec.name, spec.exe, spec.start_dir, spec.options));
  if (!appid) throw new Error("Steam did not create the tile");
  // a new shortcut is named after its executable until it is renamed
  apps.SetShortcutName?.(appid, spec.name);
  if (spec.options) apps.SetShortcutLaunchOptions?.(appid, spec.options);
  if (spec.compat_tool) apps.SpecifyCompatTool?.(appid, spec.compat_tool);
  return appid;
}

// false once the user has deleted the tile in Steam
export function tileExists(appid: number | undefined): boolean {
  if (!appid) return false;
  try {
    return !!appStore?.GetAppOverviewByAppID?.(appid);
  } catch {
    return false;
  }
}

// Steam's custom artwork slots, as its own "Set Custom Artwork" fills them
const ASSET = { grid_p: 0, hero: 1, logo: 2, grid_l: 3, icon: 4 } as const;

export async function setArtwork(appid: number, art: Partial<Record<keyof typeof ASSET, string>>) {
  const apps = SteamClient?.Apps;
  if (!apps?.SetCustomArtworkForApp) return 0;
  let set = 0;
  for (const [slot, data] of Object.entries(art)) {
    if (!data) continue;
    await apps.SetCustomArtworkForApp(appid, data, "png", ASSET[slot as keyof typeof ASSET]);
    set++;
  }
  return set;
}

export function removeTile(appid: number) {
  SteamClient?.Apps?.RemoveShortcut?.(appid);
}

// a non-Steam shortcut starts by its 64-bit game id: (appid << 32) | 0x02000000
export function launchTile(appid: number) {
  const gameid = ((BigInt(appid >>> 0) << 32n) | 0x02000000n).toString();
  SteamClient.Apps.RunGame(gameid, "", -1, 100);
}
