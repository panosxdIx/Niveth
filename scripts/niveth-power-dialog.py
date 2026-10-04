#!/usr/bin/env python3

import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""

    if mode == "restart":
        title = "Niveth System Cleaner"
        message = (
            "Your system is ready to restart.\n\n"
            "You can clean temporary data before restarting."
        )
        clean_text = "Clean & Restart"
        normal_text = "Restart without cleaning"

    elif mode == "shutdown":
        title = "Niveth System Cleaner"
        message = (
            "Your system is ready to shut down.\n\n"
            "You can clean temporary data before shutting down."
        )
        clean_text = "Clean & Shutdown"
        normal_text = "Shutdown without cleaning"

    else:
        print("cancel")
        return 1

    dialog = Gtk.Dialog(
        title=title,
        modal=True,
        destroy_with_parent=True,
    )

    dialog.set_default_size(520, -1)
    dialog.set_resizable(False)
    dialog.set_position(Gtk.WindowPosition.CENTER)

    content = dialog.get_content_area()
    content.set_spacing(14)
    content.set_border_width(24)

    title_label = Gtk.Label()
    title_label.set_markup(
        "<span size='x-large' weight='bold'>"
        "Niveth System Cleaner"
        "</span>"
    )
    title_label.set_xalign(0)

    message_label = Gtk.Label(label=message)
    message_label.set_xalign(0)
    message_label.set_line_wrap(True)

    content.pack_start(title_label, False, False, 0)
    content.pack_start(message_label, False, False, 0)

    clean_button = dialog.add_button(
        clean_text,
        1,
    )

    normal_button = dialog.add_button(
        normal_text,
        2,
    )

    cancel_button = dialog.add_button(
        "Cancel",
        0,
    )

    dialog.set_default_response(1)

    dialog.show_all()

    response = dialog.run()
    dialog.destroy()

    if response == 1:
        print("clean")
        return 0

    if response == 2:
        print("normal")
        return 0

    print("cancel")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
