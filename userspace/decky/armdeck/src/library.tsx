// The Library page (opened from the ARMDeck panel in Quick Access): the emulator catalog, each
// installed with one press and given its own tile in the Steam library, "Add a game", which
// gives any game file its tile, and the Inbox, a folder whose contents are placed and given tiles
// by themselves (inbox.py).
import {
  ConfirmModal,
  DialogButton,
  Field,
  Focusable,
  ModalRoot,
  ProgressBarWithInfo,
  showModal,
  TextField,
} from "@decky/ui";
import { callable, FileSelectionType, openFilePicker, toaster } from "@decky/api";
import { useEffect, useState } from "react";
import qrcode from "qrcode-generator";
import { addTile, launchTile, removeTile, setArtwork, TileSpec, tileExists } from "./shortcuts";

type Emu = {
  id: string;
  name: string;
  systems: string;
  source: string;
  size: number;
  installed: boolean;
  version: string | null;
  available: string;
};
type Job = {
  id: string;
  action: "install" | "remove" | "unpack";
  phase: string;
  done: number;
  total: number;
  error: string | null;
  finished: boolean;
};
type Status = { emulators: Emu[]; job: Job | null; free: number };
type Tiles = Record<string, { appid: number; name: string }>;

const libraryStatus = callable<[], Status>("library_status");
const libraryInstall = callable<[id: string], Job>("library_install");
const libraryRemove = callable<[id: string], Job>("library_remove");
const libraryCancel = callable<[], boolean>("library_cancel");
const libraryTiles = callable<[], Tiles>("library_tiles");
const emulatorSpec = callable<[id: string], TileSpec>("library_emulator_spec");
const tileCreated = callable<[key: string, appid: number, name: string], boolean>(
  "library_tile_created"
);
const tileForget = callable<[key: string], boolean>("library_tile_forget");
const libraryArtwork = callable<[path: string, kind: string], Record<string, string>>(
  "library_artwork"
);

// a new game tile gets its artwork in the background (libretro-thumbnails, emulated games only);
// a tile without it keeps Steam's plain one
function addArtwork(appid: number, spec: TileSpec) {
  if (!spec.kind || spec.kind === "windows" || spec.kind === "native") return;
  const path = spec.key.slice("game:".length);
  libraryArtwork(path, spec.kind)
    .then((art) => setArtwork(appid, art))
    .catch(() => undefined);
}

type Inspect = {
  path: string;
  kind: string | null;
  name: string | null;
  how: string | null;
  choices: { id: string; name: string }[];
  needs: { id: string; name: string } | null;
  existing: { appid: number; name: string } | null;
  error: string | null;
};
const pickFolder = callable<[], string>("library_pick_folder");
const libraryInspect = callable<[path: string, system: string], Inspect>("library_inspect");
const gameSpec = callable<[path: string, kind: string, name: string], TileSpec>(
  "library_game_spec"
);

type InboxView = { tiles: TileSpec[]; placed: string[]; notes: string[] };
const inboxStart = callable<[], string>("library_inbox_start");
const inboxScan = callable<[], InboxView>("library_inbox_scan");
const libraryPending = callable<[id: string], TileSpec[]>("library_pending");

type Upload = {
  running: boolean;
  url?: string;
  closes_in?: number;
  received?: number;
  bytes?: number;
  error?: string;
};
const uploadStart = callable<[], Upload>("library_upload_start");
const uploadStop = callable<[], boolean>("library_upload_stop");
const uploadStatus = callable<[], Upload>("library_upload_status");

const mb = (bytes: number) => `${Math.round(bytes / 1e6)} MB`;
const gb = (bytes: number) => `${(bytes / 1e9).toFixed(1)} GB`;

// The emulator's tile, unless one made by the Library is still in Steam
export async function ensureEmulatorTile(id: string): Promise<number> {
  const spec = await emulatorSpec(id);
  const known = (await libraryTiles())[spec.key];
  if (known && tileExists(known.appid)) return known.appid;
  const appid = await addTile(spec);
  await tileCreated(spec.key, appid, spec.name);
  return appid;
}

// Called for every finished job, also when the page is closed (index.tsx listens all the time)
export async function onLibraryJob(job: Job) {
  if (job.error) {
    toaster.toast({ title: `ARMDeck Library: ${job.id}`, body: job.error });
    return;
  }
  // an install made before the Library unpacked AppImages, unpacked when the plugin loads
  if (job.action === "unpack") return;
  const key = `emu:${job.id}`;
  try {
    if (job.action === "install") {
      await ensureEmulatorTile(job.id);
      const waiting = await addTiles(await libraryPending(job.id));
      const more = waiting.length ? ` ${waiting.length} game(s) from the Inbox got their tiles too.` : "";
      toaster.toast({ title: "ARMDeck Library", body: `${job.id} installed; its tile is in the library.${more}` });
    } else {
      const known = (await libraryTiles())[key];
      if (known && tileExists(known.appid)) removeTile(known.appid);
      await tileForget(key);
      toaster.toast({ title: "ARMDeck Library", body: `${job.id} removed.` });
    }
  } catch (e) {
    toaster.toast({ title: "ARMDeck Library", body: String(e) });
  }
}

// tiles for games placed by the Inbox (or that waited for their emulator); the names it made
async function addTiles(specs: TileSpec[]): Promise<string[]> {
  const known = await libraryTiles();
  const made: string[] = [];
  for (const spec of specs) {
    if (tileExists(known[spec.key]?.appid)) continue;
    const appid = await addTile(spec);
    await tileCreated(spec.key, appid, spec.name);
    addArtwork(appid, spec);
    made.push(spec.name);
  }
  return made;
}

const listOf = (names: string[]) =>
  names.length <= 3 ? names.join(", ") : `${names.slice(0, 3).join(", ")} and ${names.length - 3} more`;

// Called for every pass of the Inbox that did something, also when the page is closed
export async function onInbox(view: InboxView) {
  const lines: string[] = [];
  try {
    const made = await addTiles(view.tiles);
    if (made.length) lines.push(`In your library: ${listOf(made)}.`);
  } catch (e) {
    lines.push(String(e));
  }
  if (view.placed.length) lines.push(`Placed: ${listOf(view.placed)}.`);
  if (view.notes.length) lines.push(`Left in the Inbox: ${listOf(view.notes)}.`);
  if (lines.length) toaster.toast({ title: "ARMDeck Inbox", body: lines.join(" ") });
}

// the watcher starts once the frontend listens (index.tsx), so no tile is missed
export async function startInbox() {
  try {
    await inboxStart();
  } catch (e) {
    toaster.toast({ title: "ARMDeck Inbox", body: String(e) });
  }
}

// --- Files without a cable ---

// the QR code as SVG squares, drawn by React (no HTML from a string)
function QrCode({ text, size }: { text: string; size: number }) {
  const qr = qrcode(0, "M");
  qr.addData(text);
  qr.make();
  const n = qr.getModuleCount();
  let d = "";
  for (let r = 0; r < n; r++)
    for (let c = 0; c < n; c++) if (qr.isDark(r, c)) d += `M${c + 4} ${r + 4}h1v1h-1z`;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${n + 8} ${n + 8}`} shapeRendering="crispEdges">
      <rect width={n + 8} height={n + 8} fill="#fff" />
      <path d={d} fill="#000" />
    </svg>
  );
}

function UploadModal({ first, closeModal }: { first: Upload; closeModal?: () => void }) {
  const [up, setUp] = useState<Upload>(first);
  // only while this window is open: received files and the time left
  useEffect(() => {
    const timer = setInterval(async () => setUp(await uploadStatus()), 2000);
    return () => clearInterval(timer);
  }, []);
  const stop = async () => {
    await uploadStop();
    closeModal?.();
  };
  return (
    <ModalRoot closeModal={closeModal}>
      <h3 style={{ marginTop: 0 }}>Send files to this phone</h3>
      {up.running && up.url ? (
        <div style={{ display: "flex", gap: "24px", alignItems: "center" }}>
          <QrCode text={up.url} size={220} />
          <div>
            <div>Scan the code with a phone, or open this address on a computer on the same WiFi:</div>
            <div style={{ fontFamily: "monospace", margin: "0.6em 0", wordBreak: "break-all" }}>{up.url}</div>
            <div style={{ opacity: 0.7 }}>
              Received: {up.received ?? 0} file(s), {mb(up.bytes ?? 0)}. Everything goes to the Inbox.
              The page closes by itself after {Math.ceil((up.closes_in ?? 0) / 60)} min without use.
              Keep this phone awake while it sends.
            </div>
          </div>
        </div>
      ) : (
        <div>The upload page is closed.</div>
      )}
      <Focusable style={{ display: "flex", gap: "8px", marginTop: "1em" }}>
        <DialogButton onClick={closeModal}>Keep it open</DialogButton>
        <DialogButton onClick={stop}>Close the page</DialogButton>
      </Focusable>
    </ModalRoot>
  );
}

async function openUpload() {
  try {
    const up = await uploadStart();
    if (up.error) return toast(up.error);
    showModal(<UploadModal first={up} />);
  } catch (e) {
    toast(String(e));
  }
}

// --- Add a game ---

const toast = (body: string) => {
  toaster.toast({ title: "ARMDeck Library", body });
};

// a disc image some systems share (a CHD, a CSO): the user says which console it is for
function ChooseSystem({ info, closeModal }: { info: Inspect; closeModal?: () => void }) {
  return (
    <ModalRoot closeModal={closeModal}>
      <h3 style={{ marginTop: 0 }}>Which console is this game for?</h3>
      <div style={{ opacity: 0.7, marginBottom: "1em", wordBreak: "break-all" }}>{info.path}</div>
      <Focusable style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
        {info.choices.map((c) => (
          <DialogButton
            key={c.id}
            onClick={() => {
              closeModal?.();
              addPicked(info.path, c.id);
            }}
          >
            {c.name}
          </DialogButton>
        ))}
      </Focusable>
    </ModalRoot>
  );
}

function AddGame({ info, closeModal }: { info: Inspect; closeModal?: () => void }) {
  const [name, setName] = useState(info.name ?? "");
  const add = async () => {
    try {
      const spec = await gameSpec(info.path, info.kind!, name);
      const appid = await addTile(spec);
      await tileCreated(spec.key, appid, spec.name);
      addArtwork(appid, spec);
      toast(`${spec.name} is in your library.`);
    } catch (e) {
      toast(String(e));
    }
  };
  return (
    <ConfirmModal
      strTitle="Add this game to the library?"
      strOKButtonText="Add"
      bOKDisabled={!name.trim()}
      onOK={add}
      closeModal={closeModal}
    >
      <div style={{ marginBottom: "0.5em" }}>{info.how}</div>
      <div style={{ opacity: 0.7, marginBottom: "1em", wordBreak: "break-all" }}>{info.path}</div>
      <TextField label="Name in the library" value={name} onChange={(e) => setName(e.target.value)} />
    </ConfirmModal>
  );
}

async function addPicked(path: string, system: string) {
  try {
    const info = await libraryInspect(path, system);
    if (info.error) return toast(info.error);
    if (info.choices.length) return void showModal(<ChooseSystem info={info} />);
    if (info.needs) return toast(`This game needs ${info.needs.name}: install it on this page first.`);
    if (info.existing && tileExists(info.existing.appid))
      return toast(`Already in your library as ${info.existing.name}.`);
    showModal(<AddGame info={info} />);
  } catch (e) {
    toast(String(e));
  }
}

async function addGame() {
  let picked;
  try {
    // FileSelectionType.FILE: a const enum, which exists only in the types
    picked = await openFilePicker(0 as FileSelectionType, await pickFolder(), true, true);
  } catch {
    return; // the picker was closed without a file
  }
  await addPicked(picked.realpath || picked.path, "");
}

function jobText(job: Job): string {
  if (job.total > 0) return `${job.phase}: ${mb(job.done)} of ${mb(job.total)}`;
  if (job.phase === "packages") return "installing the Fedora packages (a few minutes)";
  if (job.phase === "unpack") return "unpacking, once, so it starts faster";
  return job.phase;
}

function EmuRow({ emu, job, tiles, refresh }: {
  emu: Emu;
  job: Job | null;
  tiles: Tiles;
  refresh: () => void;
}) {
  const busy = job && !job.finished && job.id === emu.id ? job : null;
  const otherBusy = !!(job && !job.finished && job.id !== emu.id);
  const tile = tiles[`emu:${emu.id}`];
  const hasTile = tileExists(tile?.appid);

  const run = async (fn: () => Promise<unknown>) => {
    try {
      await fn();
    } catch (e) {
      toaster.toast({ title: "ARMDeck Library", body: String(e) });
    }
    refresh();
  };
  const confirmRemove = () =>
    showModal(
      <ConfirmModal
        strTitle={`Remove ${emu.name}?`}
        strDescription="The emulator and its tile go away. Your games, BIOS files and saves stay."
        strOKButtonText="Remove"
        bDestructiveWarning={true}
        onOK={() => run(() => libraryRemove(emu.id))}
      />
    );

  return (
    <Field
      label={emu.name}
      description={
        <>
          <div>{emu.systems}</div>
          <div style={{ fontSize: "0.8em", opacity: 0.7 }}>
            {emu.installed ? `Installed: ${emu.version}` : `${mb(emu.size)}, ${emu.source}`}
          </div>
          {busy && (
            <ProgressBarWithInfo
              nProgress={busy.total ? (100 * busy.done) / busy.total : undefined}
              indeterminate={!busy.total}
              sOperationText={jobText(busy)}
            />
          )}
        </>
      }
      bottomSeparator="standard"
      childrenLayout="inline"
    >
      <Focusable style={{ display: "flex", gap: "8px" }}>
        {busy && <DialogButton onClick={() => run(libraryCancel)}>Cancel</DialogButton>}
        {!busy && !emu.installed && (
          <DialogButton disabled={otherBusy} onClick={() => run(() => libraryInstall(emu.id))}>
            Install
          </DialogButton>
        )}
        {!busy && emu.installed && hasTile && (
          <DialogButton onClick={() => launchTile(tile.appid)}>Open</DialogButton>
        )}
        {!busy && emu.installed && !hasTile && (
          <DialogButton onClick={() => run(() => ensureEmulatorTile(emu.id))}>Add tile</DialogButton>
        )}
        {!busy && emu.installed && (
          <DialogButton disabled={otherBusy} onClick={confirmRemove}>Remove</DialogButton>
        )}
      </Focusable>
    </Field>
  );
}

export function LibraryPage() {
  const [status, setStatus] = useState<Status | null>(null);
  const [checking, setChecking] = useState(false);
  const [tiles, setTiles] = useState<Tiles>({});

  const refresh = async () => {
    setStatus(await libraryStatus());
    setTiles(await libraryTiles());
  };
  useEffect(() => {
    refresh();
  }, []);
  // follow a running job once a second; nothing runs while the page is idle
  const running = !!(status?.job && !status.job.finished);
  useEffect(() => {
    if (!running) return;
    const timer = setInterval(refresh, 1000);
    return () => clearInterval(timer);
  }, [running]);

  return (
    <div style={{ marginTop: "40px", height: "calc(100% - 40px)", overflowY: "scroll", padding: "0 2.8vw 4vh" }}>
      <h2 style={{ marginBottom: "0.2em" }}>ARMDeck Library</h2>
      <Field
        label="Add a game"
        description="A ROM or disc image, a Windows .exe or an ARM64 program: it gets its own tile, started the right way."
        bottomSeparator="standard"
        childrenLayout="inline"
      >
        <DialogButton onClick={addGame}>Choose a file</DialogButton>
      </Field>
      <Field
        label="Inbox"
        description="Copy games into the Inbox folder on the games partition (over USB, the network or a download): each one is recognized, moved to its place and gets its tile. Archives are unpacked; a Windows game goes in as its whole folder."
        bottomSeparator="standard"
        childrenLayout="inline"
      >
        <DialogButton
          disabled={checking}
          onClick={async () => {
            setChecking(true);
            try {
              const view = await inboxScan();
              if (!view.tiles.length && !view.placed.length && !view.notes.length)
                toast("The Inbox is empty.");
              else await onInbox(view);
            } catch (e) {
              toast(String(e));
            }
            setChecking(false);
            refresh();
          }}
        >
          {checking ? "Checking..." : "Check now"}
        </DialogButton>
      </Field>
      <Field
        label="Send files without a cable"
        description="Opens a page on the home WiFi for a few minutes, with a QR code: files and folders sent from another phone or a computer go to the Inbox."
        bottomSeparator="standard"
        childrenLayout="inline"
      >
        <DialogButton onClick={openUpload}>Show the QR code</DialogButton>
      </Field>
      <h3 style={{ marginBottom: "0.2em" }}>Emulators</h3>
      <div style={{ opacity: 0.7, marginBottom: "1em" }}>
        Each emulator gets a tile in your library. Games go in Emulation/roms on the games
        partition{status ? `; ${gb(status.free)} free` : ""}.
      </div>
      {status?.emulators.map((emu) => (
        <EmuRow key={emu.id} emu={emu} job={status.job} tiles={tiles} refresh={refresh} />
      ))}
    </div>
  );
}
