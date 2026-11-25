#!/usr/bin/env python3
"""Golden screenshot tests for Tempered Crystal.

Usage:
    python3 tempered/tests/run_tests.py [--update | --save] [TEST...]

Example:
    python3 tempered/tests/run_tests.py falkner

Each run plays a new game once and saves its state, then runs the tests in
parallel, each starting from that state.
"""

import argparse
import concurrent.futures
import filecmp
import functools
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ROM = ROOT / "temperedcrystal_test.gbc"
SYM = ROM.with_suffix(".sym")
ASM = ["rgbasm", "-Q8", "-P", "includes.asm", "-D_CRYSTAL11", "-DTEMPERED_NO_RTC", "-DTEMPERED_FIXED_RNG"]
TIMEOUT = 300

@functools.cache
def image():
    """The Docker image of headless mGBA."""
    commit = re.search(r"^ARG MGBA_COMMIT=(\w+)", (HERE / "mgba" / "Dockerfile").read_text(), re.M)[1]
    name = f"temperedcrystal-mgba:{commit[:9]}"
    if subprocess.run(["docker", "image", "inspect", name], capture_output=True).returncode:
        print(f"building {name}")
        subprocess.run(["docker", "build", "-q", "-t", name, HERE / "mgba"], check=True, stdout=subprocess.DEVNULL)
    return name


@functools.cache
def labels():
    """The ROM's labels as rgbasm definitions, for setup scripts to use."""
    found = re.findall(r"^\w+:(\w+) (\w+)$", SYM.read_text(), re.M)
    return "".join(f"DEF {name} EQU ${addr}\n" for addr, name in found)


def assemble(setup, work):
    """Assemble a setup script to work/setup, with pokecrystal's script macros and
    the ROM's labels (as addresses, e.g. for `loadmem wPartyMon1Moves, TACKLE`)."""
    (work / "labels.asm").write_text(f'{labels()}SECTION "setup", ROM0[0]\n')
    (work / "setup.asm").write_text(f"{setup}\n\tend\n")
    rgbasm = [*ASM, "-P", work / "labels.asm", "-o", work / "setup.o", work / "setup.asm"]
    rgblink = ["rgblink", "-x", "-o", work / "setup", work / "setup.o"]
    for cmd in rgbasm, rgblink:
        if (res := subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)).returncode:
            raise ValueError(res.stderr.strip())


def lua(value):
    """A Lua literal for a TOML table, array or string."""
    if isinstance(value, dict):
        return "{" + ", ".join(f"{k} = {lua(v)}" for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ", ".join(map(lua, value)) + "}"
    return json.dumps(value, ensure_ascii=False)


def run(test, results, new_game, save=False, save_new_game=False):
    """Play a test in headless mGBA from the saved new game state, and emit its
    outputs to `results`. With `save`, write a save file after setup instead of
    playing the test steps. With `save_new_game`, only play a new game and save
    its initial state."""
    shutil.rmtree(results, ignore_errors=True)
    results.mkdir(parents=True)
    with tempfile.TemporaryDirectory() as work:
        work = pathlib.Path(work)
        assemble(test.get("setup", ""), work)
        (work / "steps.lua").write_text(f"return {lua(test.get('steps', []))}\n")
        env = {
            "TC_RESULTS": "/results",
            "TC_SYM": f"/repo/{SYM.name}",
            "TC_CHARMAP": "/repo/constants/charmap.asm",
            "TC_SETUP": "/work/setup",
            "TC_STEPS": "/work/steps.lua",
        }
        if save:
            env["TC_SAVE"] = "/results/temperedcrystal.sav"
        docker = ["docker", "run", "--rm", "-v", f"{ROOT}:/repo:ro", "-v", f"{work}:/work", "-v", f"{results}:/results"]
        docker += ["-v", f"{new_game.parent}:/state"]
        env["TC_NEW_GAME"] = f"/state/{new_game.name}"
        if save_new_game:
            env["TC_NEW_GAME_SAVE"] = "1"
        docker += [arg for k, v in env.items() for arg in ("-e", f"{k}={v}")]
        script = f"/repo/{(HERE / 'play_test.lua').relative_to(ROOT)}"
        mgba = ["timeout", str(TIMEOUT), "mgba-headless", "--script", script, f"/repo/{ROM.name}"]
        with open(results / "mgba.log", "w") as log:
            passed = subprocess.run([*docker, image(), *mgba], stdout=log, stderr=subprocess.STDOUT).returncode == 0
    if passed:
        return True, ""
    log = results / "log.txt"
    return False, log.read_text().rstrip() if log.exists() else f"  crashed: see {results / 'mgba.log'}"


def save_new_game(state):
    """Play a new game and save its initial state."""
    passed, log = run({}, HERE / "results" / "new_game", state, save_new_game=True)
    if not passed or not state.exists():
        sys.exit(f"could not save the state after a new game:\n{log}")


def check(path, update, save, new_game):
    """Run the test at `path` and check its screenshot against the golden."""
    test = tomllib.loads(path.read_text())
    results, golden = HERE / "results" / path.stem, HERE / "golden" / f"{path.stem}.png"
    passed, log = run(test, results, new_game, save)
    if not passed:
        return False, log
    if save:
        return True, f"  wrote {(results / 'temperedcrystal.sav').relative_to(HERE)}"
    shot = results / "screenshot.png"
    if update:
        shutil.copy(shot, golden)
    elif not golden.exists():
        return False, f"  {shot.relative_to(HERE)} does not have a golden yet"
    elif not filecmp.cmp(shot, golden, shallow=False):
        return False, f"  {shot.relative_to(HERE)} differs from {golden.relative_to(HERE)}"
    return True, ""


def check_safely(path, update, save, new_game):
    try:
        return check(path, update, save, new_game)
    except (OSError, ValueError) as e:
        return False, f"  {path.name}: {e}"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("tests", nargs="*", help="test names (cases/<name>.toml); all of them by default")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--update", action="store_true", help="rewrite the goldens from this run")
    mode.add_argument("--save", action="store_true", help="save after the setup instead of testing")
    args = parser.parse_args()
    if not ROM.exists() or " TemperedFixedRNG\n" not in SYM.read_text():
        sys.exit(f"{ROM.name} missing or not a test build: run `make crystal_test`")
    paths = [HERE / "cases" / f"{t}.toml" for t in args.tests] or sorted((HERE / "cases").glob("*.toml"))
    failed = 0
    with tempfile.TemporaryDirectory() as state, concurrent.futures.ThreadPoolExecutor(os.cpu_count()) as pool:
        new_game = pathlib.Path(state) / "new_game.ss"
        save_new_game(new_game)
        runs = [pool.submit(check_safely, path, args.update, args.save, new_game) for path in paths]
        for path, future in zip(paths, runs):
            ok, message = future.result()
            if message:
                print(message)
            print(f"{'pass' if ok else 'FAIL'}: {path.stem}")
            failed += not ok
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
