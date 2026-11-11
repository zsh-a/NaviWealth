#!/usr/bin/env python3
"""Exercise the installed Rust client through Android's real accessibility tree.

Use a dedicated test device. Creates uniquely named synthetic accounts and records;
existing data is retained unless --reset is explicitly supplied. ADB_SERVER_SOCKET
and ANDROID_ADB_SERVER_PORT are inherited. Screenshots use physical screencap,
including native dialog windows, rather than the nsh development test agent.
"""

import argparse
import datetime
import json
from pathlib import Path
import re
import shlex
import subprocess
import time
import xml.etree.ElementTree as ET


class Device:
    def __init__(self, args):
        self.args = args
        self.command = [args.adb, "-s", args.serial]
        self.evidence = {"serial": args.serial, "package": args.package, "checks": []}
        self.output = args.output
        self.output.mkdir(parents=True, exist_ok=True)

    def adb(self, *args):
        return subprocess.check_output(self.command + list(args), timeout=45)

    def nodes(self):
        self.adb("shell", "uiautomator", "dump", "/sdcard/naviwealth-smoke.xml")
        xml = self.adb("exec-out", "cat", "/sdcard/naviwealth-smoke.xml")
        self.last_xml = xml
        return list(ET.fromstring(xml).iter("node"))

    @staticmethod
    def label(node):
        return node.get("text") or node.get("content-desc") or ""

    def wait(self, label, present=True, timeout=20):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            nodes = self.nodes()
            matches = [n for n in nodes if self.label(n) == label]
            if bool(matches) == present:
                return matches
            time.sleep(.25)
        raise AssertionError(f"Expected {label!r} present={present}; visible: "
                             + repr([self.label(n) for n in nodes if self.label(n)]))

    def tap(self, label, last=False):
        nodes = self.wait(label)
        node = nodes[-1] if last else nodes[0]
        self.assert_package(node.get("package"))
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        self.adb("shell", "input", "tap", str((x1+x2)//2), str((y1+y2)//2))
        # Native sheets and keyboard dismissal can asynchronously relocate fields.
        time.sleep(.8)

    def fill(self, label, value):
        node = next((n for n in self.wait(label)
                     if n.get("class") == "android.widget.EditText"), None)
        if node is None:
            raise AssertionError(f"No native editable field {label!r}")
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        self.adb("shell", "input", "tap", str((x1+x2)//2), str((y1+y2)//2))
        self.adb("shell", "input", "keycombination", "113", "29")
        # adb reconstructs these arguments as a remote shell command. Quote the
        # text argument for that shell, including semicolons and apostrophes.
        self.adb("shell", "input", "text", shlex.quote(value.replace(" ", "%s")))
        time.sleep(.3)
        if node.get("password", "false").lower() != "true":
            self.wait(value)
        ime = self.adb("shell", "dumpsys", "input_method").decode(errors="replace")
        # LatinIME may retain mIsInputViewShown=true after its window is hidden.
        # Prefer the manager's actual visibility so this cannot issue an extra
        # app-navigation Back while intending only to hide the keyboard.
        manager = re.search(r"\bmInputShown=(true|false)\b", ime)
        shown = manager.group(1) == "true" if manager else "mIsInputViewShown=true" in ime
        if shown:
            self.adb("shell", "input", "keyevent", "4")
        time.sleep(.8)
        # Password fields mask their contents, so only assert plain text inputs.
        if node.get("password", "false").lower() != "true":
            self.wait(value)

    def assert_package(self, package):
        if package != self.args.package:
            raise AssertionError(f"Wrong foreground node package: {package}")

    def capture(self, name, required):
        self.wait(required)
        window = self.adb("shell", "dumpsys", "window").decode(errors="replace")
        focus = [line.strip() for line in window.splitlines()
                 if "mCurrentFocus=" in line or "mFocusedApp=" in line]
        current = [line for line in focus if "mCurrentFocus=" in line]
        if not current or not all(self.args.package in line for line in current):
            raise AssertionError(f"Wrong screenshot window: {focus}")
        self.assert_package(self.wait(required)[-1].get("package"))
        path = self.output / f"{name}.png"
        path.write_bytes(self.adb("exec-out", "screencap", "-p"))
        self.evidence.setdefault("screenshots", []).append(
            {"file": str(path), "required": required, "focus": focus})

    def check(self, label):
        self.wait(label)
        self.evidence["checks"].append(label)
        print("Verified:", label, flush=True)

    def go_home(self):
        """Unwind native route depth before touching the four business tabs.

        Global settings, account lists, and entry receipts are pushed pages.
        Android back also dismisses their native dialog/IME layers. Never
        silently discard a dirty draft or clear local data to recover navigation.
        """
        tabs = {"今日", "流水", "财富", "规划"}
        for _ in range(12):
            labels = {self.label(n) for n in self.nodes()}
            if tabs <= labels and "FinanceOS" in labels:
                return
            if "放弃未保存的修改？" in labels:
                raise AssertionError("Unsaved form blocks smoke navigation; keep or discard it explicitly")
            self.adb("shell", "input", "keyevent", "4")
            time.sleep(.6)
        raise AssertionError("Could not return to the visible FinanceOS four-tab workspace")

    def go_tab(self, label):
        """Select a business tab only after returning from native page depth."""
        aliases = {"活动": "流水", "Today": "今日", "Activity": "流水",
                   "Wealth": "财富", "Plan": "规划"}
        label = aliases.get(label, label)
        if label == "账户":
            self.go_accounts()
            return
        if label not in {"今日", "流水", "财富", "规划"}:
            raise AssertionError("Unknown business tab: " + label)
        self.go_home()
        self.tap(label, last=True)
        ready = {"今日": "财务收件箱", "流水": "筛选", "财富": "账户", "规划": "分类预算"}
        self.wait(ready[label])

    def go_accounts(self):
        self.go_tab("财富")
        self.tap("账户", last=True)
        self.wait("现金、负债与持仓账户")

    def verify_core_navigation(self):
        """Optional read-only shell coverage; no fixtures or settings are changed."""
        for tab in ("今日", "流水", "财富", "规划"):
            self.go_tab(tab)
            self.evidence["checks"].append("core-tab:" + tab)
        self.go_home()
        self.tap("设置", last=True)
        self.check("同步与账户")
        self.go_home()
        self.evidence["checks"].append("core-settings-native-back")
        self.go_tab("流水")

    def reveal_account(self, label):
        """Account lists can contain pre-existing test fixtures below the fold."""
        if any(self.label(n) == label for n in self.nodes()):
            return
        size = self.adb("shell", "wm", "size").decode()
        width, height = map(int, re.findall(r"(\d+)x(\d+)", size)[-1])
        # Use the current native scroll viewport: picker sheets are smaller
        # than the screen, while the account list uses the full content area.
        scrolls = []
        for node in self.nodes():
            if node.get("scrollable") != "true" or node.get("package") != self.args.package:
                continue
            bounds = list(map(int, re.findall(r"-?\d+", node.get("bounds", ""))))
            if len(bounds) == 4 and bounds[2] > bounds[0] and bounds[3] > bounds[1]:
                scrolls.append(bounds)
        x1, y1, x2, y2 = max(scrolls, key=lambda b: (b[2]-b[0])*(b[3]-b[1])) if scrolls else (0, height//4, width, height*4//5)
        x = (x1+x2)//2
        top, bottom = y1+(y2-y1)//5, y1+4*(y2-y1)//5
        for _ in range(2):
            self.adb("shell", "input", "swipe", str(x), str(top), str(x), str(bottom), "250")
        for _ in range(24):
            if any(self.label(n) == label for n in self.nodes()):
                return
            self.adb("shell", "input", "swipe", str(x), str(bottom), str(x), str(top), "250")
            time.sleep(.3)
        raise AssertionError("Account not found after scrolling: " + label)

    def start(self):
        self.adb("shell", "am", "start", "-n",
                 self.args.package + "/com.longbridge.nsh.AppActivity")
        time.sleep(1)
        self.wait("记一笔")
        self.go_home()

    def create_account(self, name, opening):
        print("Create account:", name, flush=True)
        self.go_accounts()
        labels = [self.label(n) for n in self.nodes()]
        add = next((label for label in ("添加", "添加账户", "添加第一个账户")
                    if label in labels), None)
        if add is None:
            raise AssertionError("No account creation action on the account list")
        self.tap(add)
        self.wait("保存账户")
        self.fill("例如：工资卡、日常现金", name)
        if opening != "0":
            self.fill("0.00", opening)
        self.tap("保存账户")
        self.reveal_account(name)

    def balance(self, name, expected):
        self.go_accounts()
        self.reveal_account(name)
        self.tap(name)
        self.check(expected + " CNY")
        self.adb("shell", "input", "keyevent", "4")
        self.wait("现金、负债与持仓账户")

    def record(self, kind, amount, source, merchant=None, destination=None):
        print("Create record:", kind, amount, flush=True)
        self.go_tab("流水")
        self.tap("记一笔")
        self.wait("0.00")
        self.tap(kind)
        if kind == "转账":
            self.check("转入账户")
        # The field label remains stable when long account names truncate.
        self.tap("账户")
        self.reveal_account(source + " · CNY")
        self.tap(source + " · CNY", last=True)
        if destination:
            # The selected long name may be visually truncated; the field's
            # stable label still identifies the native destination row.
            self.tap("转入账户")
            self.reveal_account(destination + " · CNY")
            self.tap(destination + " · CNY", last=True)
        self.fill("0.00", amount)
        if merchant:
            self.fill("商家或付款方（可选）", merchant)
        if kind == "转账":
            self.check("转入账户")
        self.capture("editor-" + {"收入": "income", "支出": "expense", "转账": "transfer"}[kind], "保存记录")
        self.tap("保存记录")
        self.go_tab("流水")


def main():
    config = json.loads((Path(__file__).resolve().parents[1] / "apps/client/nsh.json").read_text())
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--serial", required=True, help="Explicit dedicated Android test device/emulator serial")
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--package", default=config["id"])
    parser.add_argument("--version", default=config["version"])
    parser.add_argument("--build", type=int, default=config["build"])
    parser.add_argument("--output", type=Path, default=Path("/tmp/naviwealth-android-smoke"))
    parser.add_argument("--reset", action="store_true", help="Explicitly erase this package's local test data before running")
    parser.add_argument("--verify-core-navigation", action="store_true",
                        help="Also verify all four business tabs and native-back recovery from global settings (read-only)")
    args = parser.parse_args()
    device = Device(args)
    try:
        assert device.adb("get-state").decode().strip() == "device", "Device is not ready"
        package = device.adb("shell", "dumpsys", "package", args.package).decode(errors="replace")
        assert re.search(r"versionName=" + re.escape(args.version) + r"(?:\s|$)", package), "Unexpected package/version"
        assert re.search(r"versionCode=" + str(args.build) + r"(?:\s|$)", package), "Unexpected build number"
        device.evidence.update(version=args.version, build=args.build, reset=args.reset,
                               core_navigation=args.verify_core_navigation)
        if args.reset:
            assert device.adb("shell", "pm", "clear", args.package).decode().strip() == "Success"
        device.adb("shell", "am", "force-stop", args.package)
        device.start()
        if args.verify_core_navigation:
            device.verify_core_navigation()
        run_id = datetime.datetime.now().strftime("%m%d%H%M%S")
        source, destination = "SmokeDaily" + run_id, "SmokeSave" + run_id
        merchant = "SmokeCoffee" + run_id
        device.evidence["fixtures"] = dict(source=source, destination=destination, merchant=merchant)
        device.create_account(source, "12800")
        device.create_account(destination, "0")
        device.record("收入", "8500", source, "SmokeSalary" + run_id)
        device.record("支出", "68.5", source, merchant)
        device.record("转账", "2000", source, destination=destination)
        device.balance(source, "19231.50")
        device.balance(destination, "2000.00")
        device.go_tab("流水")
        device.capture("ledger", merchant)
        device.tap(merchant)
        device.tap("编辑记录")
        device.wait("68.5")
        device.fill("68.5", "80")
        device.tap("保存记录")
        device.go_tab("流水")
        device.balance(source, "19220.00")
        device.go_tab("流水")
        device.tap(merchant)
        device.tap("删除记录")
        device.capture("delete-confirmation", "删除这笔记录？")
        labels = [device.label(n) for n in device.nodes()]
        device.tap("确认删除" if "确认删除" in labels else "删除记录", last=True)
        device.go_tab("流水")
        device.wait(merchant, present=False)
        device.balance(source, "19300.00")
        device.adb("shell", "am", "force-stop", args.package)
        device.start()
        device.balance(source, "19300.00")
        device.balance(destination, "2000.00")
        device.evidence["status"] = "passed"
        print("PASS: native account/income/expense/transfer/edit/delete/restart balances verified")
    except Exception as error:
        device.evidence.update(status="failed", error=str(error))
        if hasattr(device, "last_xml"):
            (device.output / "failure.xml").write_bytes(device.last_xml)
        try:
            (device.output / "failure.png").write_bytes(device.adb("exec-out", "screencap", "-p"))
        except Exception:
            pass
        raise
    finally:
        (device.output / "evidence.json").write_text(json.dumps(device.evidence, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
