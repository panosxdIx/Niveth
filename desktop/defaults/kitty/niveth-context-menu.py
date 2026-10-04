#!/usr/bin/env python3

import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk


SOCKET = os.environ.get("KITTY_LISTEN_ON")
WINDOW_ID = os.environ.get("KITTY_WINDOW_ID", "").strip()


def run_kitty(args):
    """
    Run a Kitty remote-control command using the dedicated
    Niveth socket.
    """
    cmd = [
        "kitten",
        "@",
        "--to",
        SOCKET,
    ] + args

    try:
        if not SOCKET:
            print(
                "KITTY COMMAND ERROR: KITTY_LISTEN_ON is missing",
                file=sys.stderr,
            )
            return False

        pass_fds = ()

        if SOCKET.startswith("fd:"):
            try:
                remote_fd = int(SOCKET[3:])
                os.fstat(remote_fd)
                pass_fds = (remote_fd,)
            except (ValueError, OSError) as exc:
                print(
                    f"KITTY COMMAND ERROR: invalid remote-control FD: {exc}",
                    file=sys.stderr,
                )
                return False

        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
            check=False,
            pass_fds=pass_fds,
        )

        if result.returncode == 0:
            return True

        print(
            "KITTY COMMAND FAILED:",
            " ".join(cmd),
            file=sys.stderr,
        )
        print(result.stderr, file=sys.stderr)

    except Exception as exc:
        print(f"KITTY COMMAND ERROR: {exc}", file=sys.stderr)

    return False


def kitty_action(action):
    """
    Try exact original Kitty window first.
    Then fall back to Kitty's currently focused window.
    """

    if WINDOW_ID:
        ok = run_kitty([
            "action",
            "--match",
            f"id:{WINDOW_ID}",
            action,
        ])

        if ok:
            return True

    return run_kitty([
        "action",
        "--match",
        "state:focused",
        action,
    ])


def new_window():
    """
    Open a new top-level Kitty OS window.

    First tries to use the original window as the source,
    then falls back to the focused Kitty window.
    """

    if WINDOW_ID:
        ok = run_kitty([
            "launch",
            "--type=os-window",
            "--source-window",
            f"id:{WINDOW_ID}",
            "--cwd=current",
        ])

        if ok:
            return True

    return run_kitty([
        "launch",
        "--type=os-window",
        "--cwd=current",
    ])


class NivethContextMenu(Gtk.Application):

    def __init__(self):
        super().__init__(
            application_id="com.niveth.KittyContextMenu"
        )
        self.window = None

    def do_activate(self):
        if self.window is not None:
            self.window.present()
            return

        self.window = Gtk.ApplicationWindow(
            application=self
        )

        self.window.set_title("Niveth Terminal")
        self.window.set_default_size(310, 230)
        self.window.set_resizable(False)
        self.window.set_decorated(False)

        self.window.connect(
            "close-request",
            self.on_close
        )

        outer = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=8,
        )

        outer.set_margin_top(14)
        outer.set_margin_bottom(14)
        outer.set_margin_start(14)
        outer.set_margin_end(14)

        title = Gtk.Label(
            label="Niveth Terminal"
        )

        title.set_halign(Gtk.Align.START)
        title.add_css_class("title")

        outer.append(title)

        copy_button = Gtk.Button(
            label="Copy"
        )

        copy_button.set_hexpand(True)
        copy_button.connect(
            "clicked",
            self.do_copy
        )

        outer.append(copy_button)

        paste_button = Gtk.Button(
            label="Paste"
        )

        paste_button.set_hexpand(True)
        paste_button.connect(
            "clicked",
            self.do_paste
        )

        outer.append(paste_button)

        new_window_button = Gtk.Button(
            label="New Window"
        )

        new_window_button.set_hexpand(True)
        new_window_button.connect(
            "clicked",
            self.do_new_window
        )

        outer.append(new_window_button)

        self.window.set_child(outer)

        css = Gtk.CssProvider()

        css.load_from_data(
            """
            window {
                background-color: rgba(24, 27, 33, 0.97);
                border-radius: 16px;
            }

            box {
                background-color: transparent;
            }

            label.title {
                font-family: "Noto Sans";
                font-size: 15px;
                font-weight: 700;
                color: #ffffff;
                margin-bottom: 5px;
            }

            button {
                min-height: 42px;
                border-radius: 11px;
                font-family: "Noto Sans";
                font-size: 13px;
                font-weight: 600;
            }
            """
        )

        display = Gdk.Display.get_default()

        if display is not None:
            Gtk.StyleContext.add_provider_for_display(
                display,
                css,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )

        self.window.present()

    def on_close(self, *_args):
        self.window = None
        self.quit()
        return False

    def finish(self):
        if self.window is not None:
            self.window.close()
        else:
            self.quit()

    def do_copy(self, *_args):
        kitty_action("copy_to_clipboard")
        self.finish()

    def do_paste(self, *_args):
        kitty_action("paste_from_clipboard")
        self.finish()

    def do_new_window(self, *_args):
        new_window()
        self.finish()


if __name__ == "__main__":
    app = NivethContextMenu()
    raise SystemExit(app.run(sys.argv))
