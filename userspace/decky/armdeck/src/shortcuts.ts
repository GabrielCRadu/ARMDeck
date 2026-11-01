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

export function removeTile(appid: number) {
  SteamClient?.Apps?.RemoveShortcut?.(appid);
}

// a non-Steam shortcut starts by its 64-bit game id: (appid << 32) | 0x02000000
export function launchTile(appid: number) {
  const gameid = ((BigInt(appid >>> 0) << 32n) | 0x02000000n).toString();
  SteamClient.Apps.RunGame(gameid, "", -1, 100);
}
