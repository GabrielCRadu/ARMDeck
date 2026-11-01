# ARMDeck Decky plugin, backend. Runs inside Decky (in the "steam" container, as the normal user,
# never as root) and touches no hardware: it reads the thermal guard level and the battery
# temperature, edits lsfg-vk's configuration file, and runs the Library (emulators and non-Steam
# games, py_modules/armdeck_library). The Library's dnf installs use the container's own root
# (rootless podman: that is this user on the host), never the host's.
#
# Frame generation per game: each game gets a profile named "armdeck-<appid>" in
# ~/.config/lsfg-vk/conf.toml. The frontend puts LSFGVK_PROFILE=armdeck-<appid> (with the layer and
# TU_DEBUG=noubwc, see build-lsfg-vk.sh) in the game's Launch Options; lsfg-vk watches the file and
# applies multiplier, flow scale and performance mode while the game runs. Profiles with other
# names are kept as they are.
import asyncio
import json
import os
import tomllib

import decky

from armdeck_library import emulators, games, paths, tiles

HOME = decky.DECKY_USER_HOME
CONF = os.path.join(HOME, ".config/lsfg-vk/conf.toml")
LAYER = os.path.join(HOME, ".local/lib/lsfg-vk/liblsfg-vk-layer.so")
MANIFEST = os.path.join(HOME, ".local/share/vulkan/explicit_layer.d/"
                        "VkLayer_LSFGVK_frame_generation.json")
DLL = os.path.join(HOME, ".local/share/Steam/steamapps/common/Lossless Scaling/lsfg-vk.dll")
# op8-thermal writes its level to /run on the host; the container sees the host's /run here
THERMAL = ("/run/host/run/op8-thermal.level", "/run/op8-thermal.level")
# the battery temperature (tenths of a degree) of op8-thermal's last pause in standby
PAUSED = ("/run/host/run/op8-thermal.paused", "/run/op8-thermal.paused")
BATTERY = "/sys/class/power_supply/bq27411-0"
PREFIX = "armdeck-"
DEFAULTS = {"multiplier": 2, "flow_scale": 0.5, "performance_mode": True}
# the keys lsfg-vk 2.0.0 knows, in the order it writes them
GLOBAL_KEYS = ("dll", "allow_fp16", "log_level", "log_file")
PROFILE_KEYS = ("name", "active_in", "multiplier", "flow_scale", "performance_mode",
                "pacing_mode", "override_present_mode", "preserve_swapchain_image_count",
                "color_space", "transfer_function")


def read_text(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def load_conf():
    try:
        with open(CONF, "rb") as f:
            conf = tomllib.load(f)
    except FileNotFoundError:
        conf = {}
    conf.setdefault("version", 2)
    conf.setdefault("global", {})
    conf.setdefault("profile", [])
    return conf


def toml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)   # a TOML basic string is a JSON string for our values
    if isinstance(value, list):
        return "[ " + ", ".join(toml_value(v) for v in value) + " ]"
    raise ValueError(f"cannot write {value!r} to TOML")


def save_conf(conf):
    lines = [f"version = {toml_value(conf.get('version', 2))}", "", "[global]"]
    glob = conf.get("global", {})
    for key in GLOBAL_KEYS + tuple(k for k in glob if k not in GLOBAL_KEYS):
        if key in glob:
            lines.append(f"{key} = {toml_value(glob[key])}")
    for prof in conf.get("profile", []):
        lines += ["", "[[profile]]"]
        for key in PROFILE_KEYS + tuple(k for k in prof if k not in PROFILE_KEYS):
            if key in prof:
                lines.append(f"{key} = {toml_value(prof[key])}")
    text = "\n".join(lines) + "\n"
    tomllib.loads(text)  # never write a file lsfg-vk could not read
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    tmp = CONF + ".armdeck-new"
    with open(tmp, "w") as f:
        f.write(text)
    # lsfg-vk watches the directory (IN_CLOSE_WRITE | IN_MOVED_TO), so a rename is seen at once
    os.replace(tmp, CONF)


def find_profile(conf, appid):
    name = f"{PREFIX}{appid}"
    for prof in conf["profile"]:
        if prof.get("name") == name:
            return prof
    return None


class Plugin:
    async def status(self):
        """Thermal guard level, battery temperature and whether lsfg-vk is ready to use."""
        level = None
        for path in THERMAL:
            text = read_text(path)
            if text is not None and text.isdigit():
                level = int(text)
                break
        temp = read_text(os.path.join(BATTERY, "temp"))
        paused = None
        for path in PAUSED:
            text = read_text(path)
            if text is not None and text.isdigit():
                paused = {"battery_c": int(text) / 10, "at": int(os.stat(path).st_mtime)}
                break
        return {
            "thermal_level": level,
            "paused": paused,
            "charging": read_text(os.path.join(BATTERY, "status")) == "Charging",
            "battery_c": int(temp) / 10 if temp and temp.lstrip("-").isdigit() else None,
            "lsfg_layer": os.path.exists(LAYER) and os.path.exists(MANIFEST),
            "lsfg_dll": os.path.exists(DLL),
        }

    async def get_fg(self, appid: int):
        """This game's frame generation settings (the defaults if it has no profile yet)."""
        prof = find_profile(load_conf(), appid)
        settings = dict(DEFAULTS)
        if prof:
            for key in DEFAULTS:
                if key in prof:
                    settings[key] = prof[key]
        settings["profile"] = f"{PREFIX}{appid}"
        settings["has_profile"] = prof is not None
        return settings

    async def set_fg(self, appid: int, multiplier: int, flow_scale: float, performance_mode: bool):
        """Create or update this game's profile; lsfg-vk applies it while the game runs."""
        multiplier = max(2, min(4, int(multiplier)))
        flow_scale = round(max(0.25, min(1.0, float(flow_scale))), 2)
        conf = load_conf()
        prof = find_profile(conf, appid)
        if prof and (prof.get("multiplier"), prof.get("flow_scale"),
                     prof.get("performance_mode")) == (multiplier, flow_scale,
                                                       bool(performance_mode)):
            return True   # unchanged: no write, so lsfg-vk does not rebuild for nothing
        if prof is None:
            prof = {"name": f"{PREFIX}{appid}", "active_in": [str(appid)],
                    "pacing_mode": "vsync", "override_present_mode": True,
                    "preserve_swapchain_image_count": False}
            conf["profile"].append(prof)
        prof.update(multiplier=multiplier, flow_scale=flow_scale,
                    performance_mode=bool(performance_mode))
        save_conf(conf)
        decky.logger.info(f"frame generation for {appid}: x{multiplier}, flow {flow_scale}, "
                          f"performance {bool(performance_mode)}")
        return True

    # --- Library: emulators (TODO 38) ---

    async def library_status(self):
        """The catalog with what is installed, the running job and the free space."""
        return await asyncio.to_thread(emulators.status)

    async def library_install(self, emu_id: str):
        return emulators.start(emu_id, "install", self._job_finished)

    async def library_remove(self, emu_id: str):
        return emulators.start(emu_id, "remove", self._job_finished)

    async def library_cancel(self):
        emulators.cancel()
        return True

    async def library_tiles(self):
        return tiles.load()

    async def library_emulator_spec(self, emu_id: str):
        """The tile of an installed emulator: its own window (settings, its own game list)."""
        return tiles.emulator_spec(emulators.catalog()[emu_id])

    async def library_pick_folder(self):
        """Where "Add a game" opens the file picker: the ROM folders, else the games partition."""
        for d in (paths.roms(), paths.games()):
            if os.path.isdir(d):
                return d
        return HOME

    async def library_inspect(self, path: str, system: str = ""):
        return await asyncio.to_thread(games.inspect, path, system or None)

    async def library_game_spec(self, path: str, kind: str, name: str):
        return games.spec(path, kind, name)

    async def library_tile_created(self, key: str, appid: int, name: str):
        tiles.created(key, appid, name)
        decky.logger.info(f"tile {key}: appid {appid} ({name})")
        return True

    async def library_tile_forget(self, key: str):
        tiles.forget(key)
        return True

    def _job_finished(self, view):
        # runs in the job's thread; the frontend makes or removes the tile when it hears this
        decky.logger.info(f"library job finished: {view}")
        asyncio.run_coroutine_threadsafe(decky.emit("armdeck_library_job", view), self.loop)
        if view["action"] == "unpack":
            self._unpack_next()

    def _unpack_next(self):
        """Unpack the next installed AppImage that has no unpacked copy yet, one job at a time,
        each emulator tried once per load."""
        for emu_id in emulators.pending_unpacks():
            if emu_id in self.unpack_tried:
                continue
            self.unpack_tried.add(emu_id)
            try:
                emulators.start(emu_id, "unpack", self._job_finished)
                decky.logger.info(f"unpacking {emu_id}'s AppImage")
            except RuntimeError as e:
                decky.logger.info(f"unpacking later: {e}")   # a job the user started goes first
            return

    async def _main(self):
        self.loop = asyncio.get_running_loop()
        self.unpack_tried = set()
        try:
            changed = paths.install_launcher()
            if changed:
                decky.logger.info(f"launcher files updated in {paths.LIB}: {changed}")
        except OSError as e:
            decky.logger.error(f"could not install the launcher files: {e}")
        try:
            await asyncio.to_thread(self._unpack_next)
        except (OSError, ValueError) as e:
            decky.logger.error(f"could not look for AppImages to unpack: {e}")
        decky.logger.info("ARMDeck plugin loaded")

    async def _unload(self):
        pass
