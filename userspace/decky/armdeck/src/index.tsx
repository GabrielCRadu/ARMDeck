// ARMDeck Decky plugin, frontend: a Quick Access panel with frame generation for the running game
// (lsfg-vk, see userspace/steam/build-lsfg-vk.sh) and the thermal guard level (op8-thermal).
import {
  PanelSection,
  PanelSectionRow,
  ToggleField,
  SliderField,
  Field,
  Router,
  staticClasses,
} from "@decky/ui";
import { callable, definePlugin, toaster } from "@decky/api";
import { useEffect, useRef, useState } from "react";
import { FaMicrochip } from "react-icons/fa";

type Status = {
  thermal_level: number | null;
  battery_c: number | null;
  lsfg_layer: boolean;
  lsfg_dll: boolean;
};
type Fg = {
  multiplier: number;
  flow_scale: number;
  performance_mode: boolean;
  profile: string;
  has_profile: boolean;
};

const getStatus = callable<[], Status>("status");
const getFg = callable<[appid: number], Fg>("get_fg");
const setFg = callable<
  [appid: number, multiplier: number, flow_scale: number, performance_mode: boolean],
  boolean
>("set_fg");

declare const SteamClient: any;

// What the plugin adds to a game's Launch Options: the lsfg-vk layer (explicit, so it sits below
// MangoHud and the Frame Limit counts real frames), its profile for this game, and TU_DEBUG=noubwc
// (Turnip refuses lsfg-vk's shared images otherwise). Anything else in the options is kept.
const fgVars = (appid: number) =>
  `TU_DEBUG=noubwc VK_LOADER_LAYERS_ENABLE=VK_LAYER_LSFGVK_frame_generation LSFGVK_PROFILE=armdeck-${appid}`;
const FG_RE =
  /\s*TU_DEBUG=noubwc VK_LOADER_LAYERS_ENABLE=VK_LAYER_LSFGVK_frame_generation LSFGVK_PROFILE=armdeck-\d+/g;
// the same, without the "g" flag: a global regex keeps state between .test() calls
const FG_TEST = new RegExp(FG_RE.source);

function withoutFg(opts: string): string {
  const rest = opts.replace(FG_RE, "").trim();
  return rest === "%command%" ? "" : rest;
}

function withFg(opts: string, appid: number): string {
  const rest = withoutFg(opts);
  if (!rest) return `${fgVars(appid)} %command%`;
  if (rest.includes("%command%")) return `${fgVars(appid)} ${rest}`;
  // options without %command% are arguments for the game; they go after it
  return `${fgVars(appid)} %command% ${rest}`;
}

// The game's current Launch Options, straight from Steam (null if Steam does not answer)
function launchOptions(appid: number): Promise<string | null> {
  return new Promise((resolve) => {
    let done = false;
    let reg: { unregister(): void } | undefined;
    const finish = (value: string | null) => {
      if (done) return;
      done = true;
      reg?.unregister();
      resolve(value);
    };
    try {
      reg = SteamClient.Apps.RegisterForAppDetails(appid, (details: any) =>
        finish(typeof details?.strLaunchOptions === "string" ? details.strLaunchOptions : null)
      );
    } catch {
      finish(null);
    }
    setTimeout(() => finish(null), 3000);
  });
}

const SAVE_DELAY_MS = 800;

function thermalText(level: number | null): string {
  if (level === null) return "unknown";
  if (level === 0) return "0 (no limit)";
  return `${level} of 4 (big cores and GPU limited)`;
}

function Content() {
  const app = Router.MainRunningApp;
  const appid = app ? Number(app.appid) : 0;
  const [status, setStatus] = useState<Status | null>(null);
  const [fg, setFgState] = useState<Fg | null>(null);
  const [enabled, setEnabled] = useState<boolean | null>(null);

  useEffect(() => {
    let alive = true;
    const poll = async () => {
      const s = await getStatus();
      if (alive) setStatus(s);
    };
    poll();
    const timer = setInterval(poll, 2000);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, []);

  useEffect(() => {
    if (!appid) return;
    getFg(appid).then(setFgState);
    launchOptions(appid).then((opts) => setEnabled(opts === null ? null : FG_TEST.test(opts)));
  }, [appid]);

  // lsfg-vk rebuilds its whole pipeline on every change of the file, and several rebuilds in a
  // row while the game ran froze Tomb Raider (12 writes in 3 s while a slider moved, 2026-10-06).
  // The panel follows the slider at once; the file is written once, when it has been still for
  // SAVE_DELAY_MS.
  const pending = useRef<number | undefined>(undefined);
  useEffect(() => () => window.clearTimeout(pending.current), []);
  const save = (next: Fg) => {
    setFgState(next);
    window.clearTimeout(pending.current);
    pending.current = window.setTimeout(() => {
      setFg(appid, next.multiplier, next.flow_scale, next.performance_mode);
    }, SAVE_DELAY_MS);
  };

  const toggle = async (on: boolean) => {
    const opts = await launchOptions(appid);
    if (opts === null) {
      toaster.toast({ title: "ARMDeck", body: "Steam did not return this game's launch options; nothing changed." });
      return;
    }
    if (on && fg) await setFg(appid, fg.multiplier, fg.flow_scale, fg.performance_mode);
    SteamClient.Apps.SetAppLaunchOptions(appid, on ? withFg(opts, appid) : withoutFg(opts));
    setEnabled(on);
    toaster.toast({
      title: "Frame generation " + (on ? "on" : "off"),
      body: "Takes effect the next time the game starts.",
    });
  };

  const ready = status?.lsfg_layer && status?.lsfg_dll;

  return (
    <>
      <PanelSection title="Frame generation">
        {!app && (
          <PanelSectionRow>
            <Field label="Start a game to set it up" />
          </PanelSectionRow>
        )}
        {app && status && !ready && (
          <PanelSectionRow>
            <Field
              label="lsfg-vk is not ready"
              description={!status.lsfg_layer
                ? "Run build-lsfg-vk.sh in the container."
                : "Install Lossless Scaling from its lsfg-vk beta branch."}
            />
          </PanelSectionRow>
        )}
        {app && ready && fg && (
          <>
            <PanelSectionRow>
              <ToggleField
                label={app.display_name}
                description="Vulkan games only. Turning it on or off applies at the next start."
                checked={enabled === true}
                disabled={enabled === null}
                onChange={toggle}
              />
            </PanelSectionRow>
            <PanelSectionRow>
              <SliderField
                label="Multiplier"
                description="Frames shown per real frame"
                value={fg.multiplier}
                min={2}
                max={4}
                step={1}
                notchCount={3}
                notchLabels={[
                  { notchIndex: 0, label: "2x", value: 2 },
                  { notchIndex: 1, label: "3x", value: 3 },
                  { notchIndex: 2, label: "4x", value: 4 },
                ]}
                notchTicksVisible={true}
                onChange={(v) => save({ ...fg, multiplier: v })}
              />
            </PanelSectionRow>
            <PanelSectionRow>
              <SliderField
                label="Flow scale"
                description="Lower is faster and blurrier"
                value={Math.round(fg.flow_scale * 100)}
                min={25}
                max={100}
                step={5}
                showValue={true}
                valueSuffix="%"
                onChange={(v) => save({ ...fg, flow_scale: v / 100 })}
              />
            </PanelSectionRow>
            <PanelSectionRow>
              <ToggleField
                label="Performance mode"
                description="Needed on this GPU: the full mode is far too slow"
                checked={fg.performance_mode}
                onChange={(v) => save({ ...fg, performance_mode: v })}
              />
            </PanelSectionRow>
          </>
        )}
      </PanelSection>
      <PanelSection title="System">
        <PanelSectionRow>
          <Field label="Thermal guard">{thermalText(status?.thermal_level ?? null)}</Field>
        </PanelSectionRow>
        <PanelSectionRow>
          <Field label="Battery">
            {status?.battery_c != null ? `${status.battery_c.toFixed(1)} °C` : "unknown"}
          </Field>
        </PanelSectionRow>
      </PanelSection>
    </>
  );
}

export default definePlugin(() => ({
  name: "ARMDeck",
  titleView: <div className={staticClasses.Title}>ARMDeck</div>,
  content: <Content />,
  icon: <FaMicrochip />,
}));
