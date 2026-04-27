import json
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parent
OUTPUT_DIR = ROOT.parent / "shadow-2026_invite"
DATA_DIR_NAME = "data"

ENGINE_SRC = ROOT / "bin" / "hg_lua-win-x64"
ENGINE_DST_NAME = "engine"
ASSETS_SRC = ROOT / "assets_compiled"
ASSETS_DST_NAME = "assets_compiled"
LAUNCHER_CONFIG_SRC = ROOT / "launcher.json"
LAUNCHER_BINARY_SRC_NAME = "launcher_noconsole.exe"
LAUNCHER_BINARY_DST_NAME = "launcher.exe"

DATA_ARCHIVE_NAME = "data.nac"
LEGACY_ARCHIVE_TOOL = (
    ENGINE_SRC
    / "harfang"
    / "assetc"
    / "toolchains"
    / "host-windows-x64-target-windows-x64"
    / "legacy_archive.exe"
)

LAUNCHER_RUNTIME_FILES = [
    "glfw3.dll",
    "harfang.dll",
    "lua54.dll",
    "say.dll"
]

ENGINE_EXCLUDE_FILES = {
    "launcher.exe",
    "launcher_noconsole.exe",
}

OPTIONAL_FILES = [
    "shadow-26-invite.nfo",
    "screenshot.png",
]

LUA_EXCLUDES = {
    "_extract_nodes_to_instances.lua",
}

ENGINE_PRUNE_DIRS = [
    Path("harfang") / "assetc",
]

START_DEMO_BAT = """@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath 'engine\\lua.exe' -ArgumentList 'main.lua' -WorkingDirectory '%CD%'" >NUL 2>NUL
if errorlevel 1 (
    engine\\lua.exe main.lua
)
"""

LAUNCHER_CONFIG = {
    "entry": "main.lua",
    "args": [],
}


def log(message: str) -> None:
    print(message)


def require_directory(path: Path, label: str) -> None:
    if not path.is_dir():
        raise FileNotFoundError(f"Missing {label}: {path}")


def require_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"Missing {label}: {path}")


def reset_output_directory(path: Path) -> None:
    if path.exists():
        log(f"Cleaning existing output: {path}")
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def find_luac() -> str | None:
    candidates = [
        ENGINE_SRC / "luac.exe",
        shutil.which("luac.exe"),
        shutil.which("luac"),
    ]

    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return str(candidate)
    return None


def package_lua_scripts(output_dir: Path) -> None:
    luac = find_luac()
    lua_files = sorted(
        path for path in ROOT.glob("*.lua")
        if path.name not in LUA_EXCLUDES
    )

    if not lua_files:
        log("No Lua scripts found to package.")
        return

    if luac is None:
        log("No luac executable found, copying Lua sources as-is.")
        for script in lua_files:
            shutil.copy2(script, output_dir / script.name)
        return

    log(f"Using luac: {luac}")
    for script in lua_files:
        dst = output_dir / script.name
        cmd = [luac, "-s", "-o", str(dst), str(script)]
        log(" ".join(cmd))
        subprocess.run(cmd, check=True)


def copy_launcher_runtime(output_dir: Path) -> None:
    launcher_src = ENGINE_SRC / LAUNCHER_BINARY_SRC_NAME
    log(f"Copying launcher runtime: {LAUNCHER_BINARY_SRC_NAME} -> {LAUNCHER_BINARY_DST_NAME}")
    shutil.copy2(launcher_src, output_dir / LAUNCHER_BINARY_DST_NAME)

    for file_name in LAUNCHER_RUNTIME_FILES:
        src = ENGINE_SRC / file_name
        log(f"Copying launcher runtime: {file_name}")
        shutil.copy2(src, output_dir / file_name)


def copy_engine(data_dir: Path) -> None:
    engine_dst = data_dir / ENGINE_DST_NAME
    shutil.copytree(ENGINE_SRC, engine_dst)

    for file_name in ENGINE_EXCLUDE_FILES:
        excluded_path = engine_dst / file_name
        if excluded_path.exists():
            log(f"Removing engine file from data package: {excluded_path}")
            excluded_path.unlink()

    for relative_dir in ENGINE_PRUNE_DIRS:
        prune_path = engine_dst / relative_dir
        if prune_path.exists():
            log(f"Pruning engine content: {prune_path}")
            shutil.rmtree(prune_path)


def copy_assets(data_dir: Path) -> None:
    shutil.copytree(ASSETS_SRC, data_dir / ASSETS_DST_NAME)


def copy_optional_files(output_dir: Path) -> None:
    for file_name in OPTIONAL_FILES:
        src = ROOT / file_name
        if src.exists():
            log(f"Copying optional file: {src.name}")
            shutil.copy2(src, output_dir / src.name)


def write_launcher(output_dir: Path) -> None:
    launcher_path = output_dir / "start-demo.bat"
    launcher_path.write_text(START_DEMO_BAT, encoding="ascii", newline="\r\n")


def pack_data_archive(data_dir: Path, archive_path: Path) -> None:
    cmd = [
        str(LEGACY_ARCHIVE_TOOL),
        "pack",
        "-f",
        str(data_dir),
        str(archive_path),
    ]
    log(" ".join(cmd))
    subprocess.run(cmd, check=True)


def write_launcher_config(data_dir: Path) -> None:
    launcher_config_path = data_dir / "launcher.json"
    if LAUNCHER_CONFIG_SRC.exists():
        log(f"Copying launcher config: {LAUNCHER_CONFIG_SRC.name}")
        shutil.copy2(LAUNCHER_CONFIG_SRC, launcher_config_path)
        return

    launcher_config_path.write_text(
        json.dumps(LAUNCHER_CONFIG, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    require_directory(ENGINE_SRC, "engine directory")
    require_directory(ASSETS_SRC, "compiled assets directory")
    require_file(ENGINE_SRC / LAUNCHER_BINARY_SRC_NAME, f"launcher runtime file {LAUNCHER_BINARY_SRC_NAME}")
    require_file(LEGACY_ARCHIVE_TOOL, "legacy_archive tool")
    for file_name in LAUNCHER_RUNTIME_FILES:
        require_file(ENGINE_SRC / file_name, f"launcher runtime file {file_name}")

    reset_output_directory(OUTPUT_DIR)
    data_dir = OUTPUT_DIR / DATA_DIR_NAME
    data_dir.mkdir(parents=True, exist_ok=True)

    copy_launcher_runtime(OUTPUT_DIR)
    package_lua_scripts(data_dir)
    copy_engine(data_dir)
    copy_assets(data_dir)
    copy_optional_files(OUTPUT_DIR)
    write_launcher(data_dir)
    write_launcher_config(data_dir)

    archive_path = OUTPUT_DIR / DATA_ARCHIVE_NAME
    pack_data_archive(data_dir, archive_path)
    log(f"Removing staging directory: {data_dir}")
    shutil.rmtree(data_dir)

    log(f"Package ready: {OUTPUT_DIR}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        log(f"Packaging failed while running: {' '.join(exc.cmd)}")
        raise SystemExit(exc.returncode)
    except Exception as exc:
        log(f"Packaging failed: {exc}")
        raise SystemExit(1)
