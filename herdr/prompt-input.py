#!/usr/bin/env python3

import os
import select
import sys
import termios
import unicodedata
from typing import Optional


ESCAPE = b"\x1b"
PASTE_END = b"\x1b[201~"
SEQUENCES = {
    b"\x1b[13;5u": "submit",
    b"\x1b[27;5;13~": "submit",
    b"\x1b[A": "up",
    b"\x1b[B": "down",
    b"\x1b[C": "right",
    b"\x1b[D": "left",
    b"\x1b[H": "home",
    b"\x1b[F": "end",
    b"\x1b[1~": "home",
    b"\x1b[4~": "end",
    b"\x1b[3~": "delete",
    b"\x1b[200~": "paste",
}


def character_width(character: str) -> int:
    if unicodedata.combining(character):
        return 0
    if unicodedata.east_asian_width(character) in {"W", "F"}:
        return 2
    return 1


def display_text(character: str) -> str:
    if character == "\t":
        return "    "
    return character


def wrapped_rows(buffer: list[str], cursor: int, width: int) -> tuple[list[str], int, int]:
    rows = [""]
    row = 0
    column = 0
    cursor_row = 0
    cursor_column = 0

    for index, character in enumerate(buffer):
        if index == cursor:
            cursor_row = row
            cursor_column = column

        if character == "\n":
            rows.append("")
            row += 1
            column = 0
            continue

        rendered = display_text(character)
        rendered_width = sum(character_width(value) for value in rendered)
        if column and column + rendered_width > width:
            rows.append("")
            row += 1
            column = 0
        rows[row] += rendered
        column += rendered_width

    if cursor == len(buffer):
        cursor_row = row
        cursor_column = column

    return rows, cursor_row, cursor_column


def render(screen, buffer: list[str], cursor: int) -> None:
    try:
        size = os.get_terminal_size(screen.fileno())
    except OSError:
        size = os.terminal_size((80, 24))
    width = max(20, size.columns - 1)
    content_height = max(1, size.lines - 3)
    rows, cursor_row, cursor_column = wrapped_rows(buffer, cursor, width)
    first_row = max(0, cursor_row - content_height + 1)
    visible_rows = rows[first_row : first_row + content_height]

    screen.write("\x1b[2J\x1b[H")
    screen.write("\x1b[1mInitial prompt\x1b[0m\n")
    screen.write("Enter: newline | Ctrl+Enter: submit | Esc: skip\n")
    screen.write("-" * width + "\n")
    screen.write("\n".join(visible_rows))
    screen.write(
        f"\x1b[{4 + cursor_row - first_row};{min(cursor_column + 1, size.columns)}H"
    )
    screen.flush()


def read_escape_sequence(input_fd: int) -> str:
    sequence = bytearray(ESCAPE)
    while len(sequence) < 32:
        exact_match = SEQUENCES.get(bytes(sequence))
        has_longer_match = any(
            candidate.startswith(sequence) and len(candidate) > len(sequence)
            for candidate in SEQUENCES
        )
        if exact_match is not None and not has_longer_match:
            return exact_match
        if not has_longer_match and len(sequence) > 1:
            return "unknown"
        readable, _, _ = select.select([input_fd], [], [], 0.05)
        if not readable:
            return "skip" if sequence == ESCAPE else "unknown"
        sequence.extend(os.read(input_fd, 1))
    return "unknown"


def read_utf8_character(input_fd: int, first_byte: bytes) -> Optional[str]:
    value = first_byte[0]
    if value < 0x80:
        return first_byte.decode()
    if value & 0xE0 == 0xC0:
        remaining = 1
    elif value & 0xF0 == 0xE0:
        remaining = 2
    elif value & 0xF8 == 0xF0:
        remaining = 3
    else:
        return None

    encoded = first_byte
    for _ in range(remaining):
        encoded += os.read(input_fd, 1)
    try:
        return encoded.decode("utf-8")
    except UnicodeDecodeError:
        return None


def read_paste(input_fd: int) -> str:
    pasted = bytearray()
    while not pasted.endswith(PASTE_END):
        pasted.extend(os.read(input_fd, 1))
    return pasted[: -len(PASTE_END)].decode("utf-8", errors="replace")


def clean_text(text: str) -> list[str]:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    return [
        character
        for character in normalized
        if character in {"\n", "\t"} or (character >= " " and character != "\x7f")
    ]


def line_start(buffer: list[str], cursor: int) -> int:
    for index in range(cursor - 1, -1, -1):
        if buffer[index] == "\n":
            return index + 1
    return 0


def line_end(buffer: list[str], cursor: int) -> int:
    try:
        return buffer.index("\n", cursor)
    except ValueError:
        return len(buffer)


def move_vertically(buffer: list[str], cursor: int, direction: int) -> int:
    current_start = line_start(buffer, cursor)
    column = cursor - current_start
    if direction < 0:
        if current_start == 0:
            return cursor
        target_end = current_start - 1
        target_start = line_start(buffer, target_end)
    else:
        current_end = line_end(buffer, cursor)
        if current_end == len(buffer):
            return cursor
        target_start = current_end + 1
        target_end = line_end(buffer, target_start)
    return min(target_start + column, target_end)


def collect_prompt(input_fd: int, screen) -> tuple[str, int]:
    buffer: list[str] = []
    cursor = 0

    while True:
        render(screen, buffer, cursor)
        byte = os.read(input_fd, 1)
        if byte == ESCAPE:
            action = read_escape_sequence(input_fd)
            if action == "submit":
                return "".join(buffer), 0
            if action == "skip":
                return "", 0
            if action == "paste":
                pasted = clean_text(read_paste(input_fd))
                buffer[cursor:cursor] = pasted
                cursor += len(pasted)
            elif action == "left":
                cursor = max(0, cursor - 1)
            elif action == "right":
                cursor = min(len(buffer), cursor + 1)
            elif action == "up":
                cursor = move_vertically(buffer, cursor, -1)
            elif action == "down":
                cursor = move_vertically(buffer, cursor, 1)
            elif action == "home":
                cursor = line_start(buffer, cursor)
            elif action == "end":
                cursor = line_end(buffer, cursor)
            elif action == "delete" and cursor < len(buffer):
                del buffer[cursor]
            continue
        if byte == b"\x03":
            return "", 130
        if byte in {b"\r", b"\n"}:
            buffer.insert(cursor, "\n")
            cursor += 1
            continue
        if byte in {b"\x08", b"\x7f"}:
            if cursor:
                cursor -= 1
                del buffer[cursor]
            continue
        if byte == b"\t":
            buffer.insert(cursor, "\t")
            cursor += 1
            continue
        character = read_utf8_character(input_fd, byte)
        if character is not None and character >= " ":
            buffer.insert(cursor, character)
            cursor += 1


def main() -> int:
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        print("prompt input requires a terminal", file=sys.stderr)
        return 1

    input_fd = sys.stdin.fileno()
    original_attributes = termios.tcgetattr(input_fd)
    screen = sys.stderr
    try:
        raw_attributes = termios.tcgetattr(input_fd)
        raw_attributes[3] &= ~(termios.ECHO | termios.ICANON | termios.ISIG)
        raw_attributes[6][termios.VMIN] = 1
        raw_attributes[6][termios.VTIME] = 0
        termios.tcsetattr(input_fd, termios.TCSADRAIN, raw_attributes)
        screen.write("\x1b[>1u\x1b[?2004h\x1b[?25h")
        screen.flush()
        prompt, status = collect_prompt(input_fd, screen)
        if status == 0:
            sys.stdout.write(prompt)
        return status
    finally:
        termios.tcsetattr(input_fd, termios.TCSADRAIN, original_attributes)
        screen.write("\x1b[?2004l\x1b[<u\x1b[2J\x1b[H")
        screen.flush()


if __name__ == "__main__":
    raise SystemExit(main())
