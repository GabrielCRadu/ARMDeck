// The Library page (opened from the ARMDeck panel in Quick Access): the emulator catalog, each
// installed with one press and given its own tile in the Steam library, and "Add a game", which
// gives any game file its tile.
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
import { addTile, launchTile, removeTile, TileSpec, tileExists } from "./shortcuts";

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
      toaster.toast({ title: "ARMDeck Library", body: `${job.id} installed; its tile is in the library.` });
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
